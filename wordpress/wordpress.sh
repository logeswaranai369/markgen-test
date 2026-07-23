#!/bin/bash

mkdir -p {/usr/local/src/wordpress/opt/cloudstack,/usr/local/src/wordpress/}

cd /usr/local/src/wordpress/opt/cloudstack && wget https://raw.githubusercontent.com/logeswaranai369/markgen-test/main/_common-files/opt/cloudstack/wordpress_cleanup.sh
cd /usr/local/src/wordpress/opt/cloudstack && wget https://raw.githubusercontent.com/logeswaranai369/markgen-test/main/_common-files/opt/cloudstack/wordpress_update.sh

cd /usr/local/src/wordpress/ && wget https://raw.githubusercontent.com/logeswaranai369/markgen-test/main/wordpress/wordpress.yaml
