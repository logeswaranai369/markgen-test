#!/bin/bash

mkdir -p {/usr/local/src/ghosttt-24-04/opt/cloudstack,/usr/local/src/ghosttt-24-04/}

cd /usr/local/src/ghosttt-24-04/opt/cloudstack && wget https://raw.githubusercontent.com/logeswaranai369/markgen-test/main/_common-files/opt/cloudstack/ghosttt-24-04_cleanup.sh
cd /usr/local/src/ghosttt-24-04/opt/cloudstack && wget https://raw.githubusercontent.com/logeswaranai369/markgen-test/main/_common-files/opt/cloudstack/ghosttt-24-04_update.sh

cd /usr/local/src/ghosttt-24-04/ && wget https://raw.githubusercontent.com/logeswaranai369/markgen-test/main/ghost/ghosttt-24-04/ghosttt-24-04.yaml
