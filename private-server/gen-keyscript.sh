#!/bin/bash

echo "#!/bin/sh"
echo "echo -n \"$(cat keyfile)\" > /run/keyfile"
