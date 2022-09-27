import io
import os
import pathlib
import socket
import textwrap
import time

import hcloud
from hcloud.ssh_keys.domain import SSHKey
from hcloud.server_types.domain import ServerType
from hcloud.images.domain import Image
from hcloud.locations.domain import Location
import fabric
from paramiko.client import MissingHostKeyPolicy


class IgnorePolicy(MissingHostKeyPolicy):
    """Custom paramiko-like policy to just accept silently any unknown host key"""

    def missing_host_key(self, client, hostname, key):
        pass


class ScriptIO(io.StringIO):
    def print(self, *objects, sep=" ", end="\n"):
        for (i, obj) in enumerate(objects):
            if i != 0:
                self.write(sep)
            self.write(str(obj))
        self.write(end)

    def print_section(self, block):
        self.write("\n" + textwrap.dedent(block).strip() + "\n")


def wait_for_port(port: int, host: str, timeout: float):
    """Wait until a port starts accepting TCP connections.

    https://gist.github.com/butla/2d9a4c0f35ea47b7452156c96a4e7b12

    Args:
        port: Port number.
        host: Host address on which the port should exist.
        timeout: In seconds. How long to wait before raising errors.
    Raises:
        TimeoutError: The port isn't accepting connection after time specified in `timeout`.
    """
    start_time = time.perf_counter()
    while True:
        try:
            with socket.create_connection((host, port), timeout=timeout):
                break
        except OSError as ex:
            time.sleep(1)
            if time.perf_counter() - start_time >= timeout:
                raise TimeoutError(
                    f"Waited too long for the port {port} on host {host} to start accepting connections."
                ) from ex


class DSL:
    def __init__(self, token):
        self.hcloud = hcloud.Client(token=token)

    def todict(self, obj):
        return dict((k, getattr(obj, k)) for k in obj.__slots__)

    def create_server(
        self,
        *,
        name,
        server_type,
        image,
        location,
        ssh_key,
        user_data=None,
        on_conflict="fail",
        **kwargs,
    ):
        if user_data is not None:
            user_data = pathlib.Path(user_data).read_text()
        while True:
            try:
                server = self.hcloud.servers.create(
                    name=name,
                    server_type=ServerType(name=server_type),
                    image=Image(name=image),
                    location=Location(name=location),
                    ssh_keys=[SSHKey(name=ssh_key)],
                    user_data=user_data,
                    **kwargs,
                    start_after_create=False,
                )
                server.action.wait_until_finished()
                print(f"created server {name}")
                return self.hcloud.servers.get_by_id(server.server.id)
            except hcloud.APIException as e:
                if e.code != "uniqueness_error":
                    raise e
                existing = self.hcloud.servers.get_by_name(name)
                if on_conflict == "replace":
                    print(f"removing existing server named {name}")
                    action = existing.delete()
                    action.wait_until_finished()
                    continue
                elif on_conflict == "ignore":
                    print(f"using existing server {name}")
                    existing.power_off().wait_until_finished()
                    return self.hcloud.servers.get_by_id(existing.id)
                else:
                    raise e
            break

    def create_volume(
        self,
        *,
        name,
        server,
        on_conflict="fail",
        **kwargs,
    ):
        while True:
            try:
                volume = self.hcloud.volumes.create(name=name, server=server, **kwargs)
                volume.action.wait_until_finished()
                for a in volume.next_actions:
                    a.wait_until_finished()
                print(f"created volume {name}")
                return self.hcloud.volumes.get_by_id(volume.volume.id)
            except hcloud.APIException as e:
                if e.code != "uniqueness_error":
                    raise e
                existing = self.hcloud.volumes.get_by_name(name)
                if on_conflict == "replace":
                    print(f"removing existing volume named {name}")
                    if existing.server is not None:
                        action = existing.detach()
                        action.wait_until_finished()
                    existing.delete()
                    continue
                elif on_conflict == "ignore":
                    print(f"using existing volume {name}")
                    if existing.server is not None and existing.server.id != server.id:
                        if existing.server is not None:
                            action = self.hcloud.volumes.detach()
                            action.wait_until_finished()
                        action = self.hcloud.volumes.attach(existing, server)
                        action.wait_until_finished()
                    return self.hcloud.volumes.get_by_id(existing.id)
                else:
                    raise e
            break

    def rescue_ssh(self, server):
        print("rebooting to rescue mode")
        if server.status != "off":
            raise ValueError("server is not off")
        response = server.enable_rescue(type="linux64")
        response.action.wait_until_finished()
        server.power_on().wait_until_finished()
        print(
            f"rescue mode {server.public_net.ipv4.ip} with password {response.root_password}"
        )
        return self.ssh(server, user="root", password=response.root_password)

    def shutdown(self, server):
        action = server.shutdown()
        action.wait_until_finished()
        for i in range(20):
            try:
                server = self.hcloud.servers.get_by_id(server.id)
                if server.status == "off":
                    break
                time.sleep(1)
            except hcloud.APIException as e:
                # If this server has self-destruction installed, then
                # this will fail, but we should detect and swallow the
                # error.
                if e.code == "not_found":
                    break
                raise e
        if server.status != "off":
            raise ValueError("the server isn't off")

    def snapshot(self, server, description):
        print("creating snapshot")
        action = server.create_image(description)
        action.action.wait_until_finished()
        return action.image

    def power_on(self, server):
        action = server.power_on()
        action.wait_until_finished()

    def delete_server(self, server):
        try:
            action = server.delete()
            action.wait_until_finished()
        except hcloud.APIException as e:
            # If this server has self-destruction installed, then
            # this will fail, but we should detect and swallow the
            # error.
            if e.code == "not_found":
                return
            raise e

    def delete_volume(self, volume):
        if not volume.delete():
            raise ValueError("failed to delete volume")

    def ssh(self, server, *, user, password=None):
        wait_for_port(22, server.public_net.ipv4.ip, 120)
        conn = fabric.Connection(
            host=server.public_net.ipv4.ip,
            user=user,
            connect_kwargs=dict(password=password),
        )
        conn.client.set_missing_host_key_policy(IgnorePolicy())
        conn.open()
        return conn

    def breakpoint(self, name, enabled_breakpoints, conn):
        if name in enabled_breakpoints:
            print(f"triggering breakpoint '{name}'")
            self.interactive_shell(conn)
        else:
            print(f"breakpoint '{name}' is disabled")

    def interactive_shell(self, conn):
        """Open an interactive shell with the given connection. Useful for debugging."""
        print(
            "Entering interactive shell. Use 'exit 0' to continue the script or 'exit 1' to abort"
        )
        conn.run("bash", pty=True)
