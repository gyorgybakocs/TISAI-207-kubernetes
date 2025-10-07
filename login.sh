#!/bin/bash

# ssh -p 18277 root@69.156.16.17 -L 8080:localhost:8080

INSTANCE_IP=${1:-"69.156.16.17"}
INSTANCE_PORT=${2:-"18277"}
