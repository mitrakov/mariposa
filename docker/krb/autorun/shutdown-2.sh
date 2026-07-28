#!/usr/bin/env bash

if [ ! -f /.dockerenv ]; then
    sudo shutdown now
fi
