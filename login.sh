#!/bin/bash

# ssh -p 58178 root@153.213.11.44 -L 8080:localhost:8080

INSTANCE_IP=${1:-"153.213.11.44"}
INSTANCE_PORT=${2:-"58178"}
