#!/bin/bash

# ssh -p 45164 root@173.185.79.174 -L 8080:localhost:8080

INSTANCE_IP=${1:-"173.185.79.174"}
INSTANCE_PORT=${2:-"45164"}
