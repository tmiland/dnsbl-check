#!/bin/bash

verbose=false

set -o pipefail

email=root
# Detect absolute and full path as well as filename of this script
cd "$(dirname "$0")" || exit
CURRDIR=$(pwd)
cd - > /dev/null || exit

PERL_ADDR_TO_QUERY='
use English;
while (<>) {
    chomp;
    if (/:/) {
        if (/::/) {
            $before = $PREMATCH;
            $after = $POSTMATCH;
        }
        else {
            $before = $_;
            $after = "";
        }
        @before = split(/:/, $before);
        @after = split(/:/, $after);
        while (@before + @after < 8) {
            push(@before, "0");
        }
        for (reverse(@before, @after)) {
            push(@numbers, reverse(split(//, sprintf("%04x", hex($_)))));
        }
    }
    else {
        @numbers = reverse(split(/\./, $_));
    }
    print(join(".", @numbers), "\n");
}
'

addrtoquery() {
    echo "$1" | perl -e "$PERL_ADDR_TO_QUERY"
}

host=$(hostname --fqdn)

host $host 1.1.1.1 | awk '/ has .*address/ {print $NF}' | sort >| /tmp/resolved.$$
(curl --silent -4 http://ifconfig.co; curl --silent -6 http://ifconfig.co) | sort >| /tmp/ifconfig.$$
comm -12 /tmp/resolved.$$ /tmp/ifconfig.$$ >| /tmp/both.$$

while read addr; do
    reverse_ip=$(addrtoquery "$addr")
    cd "${CURRDIR}" || exit
    while read dnsbl ok_results; do
        if output="$(host -W 5 $reverse_ip.$dnsbl 1.1.1.1 2>&1 |
                     grep 'has address')"; then
            if [ -n "$output" ]; then
                if [ -n "$ok_results" ]; then
                    dnsbl_addr="$(echo "$output" | awk 'NR==1{print $NF}')"
                    for ok_addr in $ok_results; do
                        if [ "$ok_addr" = "$dnsbl_addr" ]; then
                            output=""
                            break
                        fi
                    done
                fi
                if [ -n "$output" ]; then
                    echo "$host ($addr) is listed in $dnsbl"
                    echo Lookup output:
                    echo "$output" | mail -s "DNSBL Check" $email
                    continue
                fi
            fi
        fi
        if $verbose; then
            echo "$host ($addr) is not listed in $dnsbl"
        fi
    done < ./dnsbls
done < /tmp/both.$$

rm -f /tmp/*.$$
