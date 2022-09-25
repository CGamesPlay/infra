#!/usr/bin/env python3
from pprint import pprint
import io
import sys

from lib.dsl import DSL
from lib.config import args
from lib.infra import create_infra
from lib.setup_script import get_script


options = args.parse_args()

if options.show_config:
    args.print_values()
    print("Result:")
    pprint(options.__dict__, indent=2)
    sys.exit(0)

script = get_script(options)
if options.dry_run:
    print(script, end="")
    sys.exit(0)

image, volume = create_infra(options, script)

print("")
print("=" * 79)
print("")
print("Completed successfully.")
if image is not None:
    print(f"Snapshot: {image.id}")
if volume is not None:
    print(f"Volume: {volume.id}")
if image is not None and volume is not None:
    print("")
    print("To boot this volume, use a command like this:")
    print("")
    print(
        f"  hcloud server create --location {options.location} --volume {options.name} --image {image.id} --name {options.name} --type {options.server_type}"
    )
