import configargparse

args = configargparse.ArgParser(
    description="Create a bootable volume and/or snapshot to boot from a volume."
)
args.add("--show-config", action="store_true", help="show option values and exit")
args.add("--config", is_config_file=True, help="config file path")
args.add(
    "-c",
    "--create",
    choices=["volume", "snapshot"],
    nargs="*",
    default=["volume", "snapshot"],
    env_var="PS_CREATE",
    help="asset to create",
)
args.add(
    "--token",
    env_var="HCLOUD_TOKEN",
    help="Hetzner API key to use",
)
args.add(
    "--server-type",
    env_var="PS_SERVER_TYPE",
    default="cx11",
    help="type of server to use for setup (see hcloud server-type list)",
)
args.add(
    "--location",
    default="nbg1",
    env_var="PS_LOCATION",
    help="location to create the assets in (see hcloud location list)",
)
args.add(
    "--image",
    default="ubuntu-22.04",
    env_var="PS_IMAGE",
    help="image to use to create the assets (see hcloud image list)",
)
args.add(
    "--encrypt",
    action="store_true",
    help="encrypt the volume and configure the snapshot to decrypt it on boot",
)
args.add(
    "--dry-run",
    action="store_true",
    help="print the rescue-mode script required to perform the operation without actually doing it",
)
args.add(
    "--breakpoint",
    choices=["setup", "exit_rescue", "finish_initial_boot"],
    nargs="*",
    env_var="PS_BREAKPOINT",
    default=[],
    help="add breakpoints to the execution of the script",
)
args.add(
    "--on-conflict",
    choices=["fail", "replace", "ignore"],
    env_var="PS_ON_CONFLICT",
    default="fail",
    help="behavior when the server/volume already exists",
)


volume_group = args.add_argument_group(
    "Volume options", "Configuration for creating a bootable volume."
)
volume_group.add(
    "-n",
    "--name",
    env_var="PS_VOLUME_NAME",
    default="private-server",
    help="name for the bootable volume",
)
volume_group.add(
    "-s",
    "--volume-size",
    type=int,
    env_var="PS_VOLUME_SIZE",
    default=10,
    help="initial size of the bootable volume in GB (can be enlarged later)",
)
volume_group.add(
    "--user-data",
    env_var="PS_USER_DATA",
    help="file containing user-data for the initial boot",
)
volume_group.add(
    "--username",
    default="root",
    env_var="PS_USERNAME",
    help="username to login with during initial boot",
)
volume_group.add(
    "--ssh-key",
    env_var="PS_SSH_KEY",
    help="name of SSH key to use during initial boot (see hcloud ssh-key list)",
)
