import io

from .dsl import DSL


def create_infra(options, script):
    dsl = DSL(options.token)
    create_volume = "volume" in options.create
    create_snapshot = "snapshot" in options.create

    server = dsl.create_server(
        name=options.name,
        server_type=options.server_type,
        ssh_key=options.ssh_key,
        image=options.image,
        location=options.location,
        user_data=options.user_data,
        on_conflict=options.on_conflict,
    )
    volume = dsl.create_volume(
        name=options.name,
        server=server,
        size=options.volume_size,
        on_conflict=options.on_conflict,
    )
    conn = dsl.rescue_ssh(server)
    dsl.breakpoint("setup", options.breakpoint, conn)
    print("running setup script")
    conn.run("bash -s", in_stream=io.StringIO(script))
    dsl.breakpoint("exit_rescue", options.breakpoint, conn)
    conn.close()
    dsl.shutdown(server)

    image = None
    if create_snapshot:
        description = "boots from /dev/sdb"
        if options.encrypt:
            description = "decrypts + " + description
        image = dsl.snapshot(server, description)

    if create_volume:
        if options.user_data is not None:
            print(
                f"performing initial boot of {options.name} ({server.public_net.ipv4.ip})"
            )
            dsl.power_on(server)
            conn = dsl.ssh(server, user=options.username)
            conn.run("cloud-init status -w")
            dsl.breakpoint("finish_initial_boot", options.breakpoint, conn)
            dsl.shutdown(server)

    dsl.delete_server(server)

    if not create_volume:
        dsl.delete_volume(volume)
        volume = None

    return (image, volume)
