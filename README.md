# docker-bind

A Docker image of the ISC [Bind/Bind9/Named][2] DNS service that has been set
up so it is easy to configure when running inside a container.

The program is [built][11] directly from source, in order to get the latest
version, and there are both Debian and Alpine images available. Useful
configuration [files and folders](./root/etc/bind/) (similar to what is found in
the Debian packages) are included to make it simpler to set up a DNS server.

> There is also an [Ansible role][5] using this image, if that is of interest.

> :information_source: This is still a bit of work in progress, so if something
> isn't working for you I am very interested in being notified about it.

### Acknowledgments and Thanks

This repository was originally a fork of [ventz/docker-bind][1], but what was
supposed to be just a small pull request turned into a complete rewrite. While
very little of the original code remains it would be dishonest to not keep the
commit history since without it I would not have found inspiration to make my
own version.

There is also an official [Docker image][12] ([source][13]) but I found it
have some configuration options I didn't like and chose to try to build my own
instead.



# Usage

The amount of options available for Bind is absolutely enormous, and what
options to use will be very different depending on how you intend to run your
instance so I will not even try to list suggestions here. But to just get you
started we will set up a super simple forwarding server, so it becomes easier
to understand what configuration files are needed and where they are expected
to be found.

Full Bind documentation found here: https://bind9.readthedocs.io/en/stable/


## Available Environment Variables

> :information_source: It is *possible* to change these environment variables,
  but you will most likely break things.

- `BIND_LOG`: Input argument for configuring stderr or file logging (default: `-f`)
- `BIND_USER`: The username the service will run as (default: alpine=`named`, debian=`bind`)


## Configuration Files and Folders

There are five folders in this image that are good to know about:

1. `/etc/bind/local-config/` - Your custom configs -> Mount your configs here.
2. `/var/cache/bind` - Default "workdir" for Bind -> Probably good to host mount.
3. `/var/log/bind` - Recommended folder to output logs to -> Host mount if you want.
4. `/var/lib/bind` - Suggested folder to place zone files in -> Host mount if used.
5. `/entrypoint.d/` - Place any scripts that should be executed at startup here.

### 1. Your Custom Configs
When the container starts it will launch Bind which will read the main config
file `/etc/bind/named.conf`, however, that one has only the following content:

```conf
include "/etc/bind/local-config/named.conf.logging";
include "/etc/bind/local-config/named.conf.options";
include "/etc/bind/local-config/named.conf.local";
```

What this means is that these three files are expected to be present when the
container starts, and some basic (but fully functioning) examples are available
inside the [`example-configs/`](./example-configs/) folder (see how they are
mounted in the [Run section](#run)).

> :warning: Logging in Bind is a little bit weird, so if anything in the config
> is wrong it will not output any logs unless you set `BIND_LOG=-g`. Use this
> for debugging and then switch back to default.

By having all the user defined files inside this folder, it is possible for
this image to include updated version of the ["default" config](./root/etc/bind/)
files without the users having to update their paths.

### 2. The Cache
The other important location is the "working directory" (or cache) of the server
that is defined at the top of the
[`named.conf.options`](./example-configs/named.conf.options) file. This is the
location where slave zone files will be written, or other stuff that needs to be
cached, so for persistence I recommend to host mount this folder and make sure
Bind is allowed to write to it (`root:101 - 0775`).

ISC uses `/var/cache/bind` for this, so that is what we default to in this image
as well.

Please also look at the [`rndc` section](#create-rndckey) for a simple way
to create the `rndc` key needed for communicating with Bind.

### 3. The Logs
If you choose to output logs to a file, like in the
[logging example](./example-configs/named.conf.logging), the `/var/log/bind`
directory is a good location to use inside the container. Host mount it in order
to be able to read the logs outside the container.

If you are fine with just letting Docker capture and manage the logs you can
remove the "file" configuration section, and just let it output to stdout.

### 4. Your Zone Files
ISC claims that `/var/lib/bind` is "usually the place where the secondary zones
are placed", but for my personal use I just place everything inside the
[cache](#2-the-cache) directory. It is up to you, since you will either way
need to define the paths in the "zone" declarations inside the
`named.conf.options` file.


### 5. The `entrypoint` Scripts
The final location that might be of interest is the `/entrypoint.d/` folder,
since the main [`entrypoint.sh`](./entrypoint.sh) will look inside it for any
files ending with `.sh` and try to execute them in alphabetical order. This
allows you to run custom commands before the Bind service is started.

#### Input Arguments
Any extra input arguments provided as the `CMD`, when starting the image,
will be appended directly to the Bind service. Please take a look at the last
line in [`entrypoint.sh`](./entrypoint.sh) to see how it works.



## Create `rndc.key`
At the top of the [`named.conf.local`](./example-configs/named.conf.local) file
we include an "[rndc key][10]" which needs to be created manually by you as it
should be unique and secret. You can have the file written to the
`example-configs/` folder by running the following command:

```bash
docker run -it --rm \
    -v $(pwd)/example-configs:/etc/bind/local-config \
    --entrypoint=/bin/sh \
    jonasal/bind:9 \
    -c 'rndc-confgen -a -A hmac-sha256 -b 256 -u "${BIND_USER}" -c /etc/bind/local-config/rndc.key'
```


## Run

After you have read through all the steps above we can finally start the
image:


```bash
docker run -it --rm \
    -p 54:53 -p 54:53/udp -p 953:953 \
    -v $(pwd)/example-configs:/etc/bind/local-config \
    -v $(pwd)/zones:/var/cache/bind \
    jonasal/bind:9 \
    -4
```

Important to note here is that we forward port 54 on the host to the "correct"
port 53 inside the container. I do this because some Linux distributions comes
with the [`systemd-resolved`][3] service running which already use port 53.
This is a problem if you want to run this image as a real DNS server, so you
will have to [disable it][4] if it causes you trouble.

Furthermore, at the very end of the command we include `-4`, and this tells
Bind to not enable any IPv6 functionality. The reason for this is that by
default no IPv6 traffic is handled by Docker and unnecessary error messages
will be printed unless the flag is provided. Read more about this in the
[Docker Network Mode](#docker-network-mode) section.

### Verify

In order to verify that Bind works, after running the command above, is to
just make a quick query to your machine on port 54 and see if anything is
printed in the container logs.

```bash
dig @127.0.0.1 -p 54 google.se
```

### Docker Network Mode

As was previously mentioned Docker does not have [IPv6 enabled][6] by default,
so it is recommended to start Bind with the `-4` flag to tell it to run in
just IPv4 mode. But if you do want to run it for both IP versions I would
suggest you first [read this][7] to get a better understanding of the quirks
that currently exist, and I would actually suggest you just run this container
on the `host` network to make your life easier.

> Also, don't forget to change the `listen-on-v6` directive in the options
> config file.

```bash
docker run -it --rm \
    --network host \
    -v $(pwd)/example-configs:/etc/bind/local-config \
    -v $(pwd)/zones:/var/cache/bind \
    jonasal/bind:9
```

You could probably do some [fiddling][9] with [macvlan][8] to achieve the same
stuff, but I would not bother.



# Further reading

As was mentioned in the beginning there exists a plethora of ways on how to
configure Bind, so you will need to do some of your own research in order to
function just as you want. However, here is a collection of links from where
you can start your journey:

* https://wiki.debian.org/Bind9
* https://help.ubuntu.com/community/BIND9ServerHowto
* https://www.zytrax.com/books/dns/ch7/
* https://www.digitalocean.com/community/tutorials/how-to-configure-bind-as-a-private-network-dns-server-on-ubuntu-18-04
* https://kb.isc.org/docs/aa-01526
* https://www.zytrax.com/books/dns/ch7/logging.html
* https://bind9.readthedocs.io/en/stable/






[1]: https://github.com/ventz/docker-bind
[2]: https://www.isc.org/bind/
[3]: https://www.freedesktop.org/software/systemd/man/systemd-resolved.service.html
[4]: https://askubuntu.com/a/907249
[5]: https://github.com/JonasAlfredsson/ansible-role-bind_dns
[6]: https://docs.docker.com/config/daemon/ipv6/
[7]: https://github.com/robbertkl/docker-ipv6nat
[8]: https://docs.docker.com/network/macvlan/
[9]: https://gist.github.com/mikejoh/04978da4d52447ead7bdd045e878587d
[10]: https://www.interserver.net/tips/kb/what-and-how-to-use-rndc/
[11]: https://bind9.readthedocs.io/en/latest/chapter10.html
[12]: https://hub.docker.com/r/internetsystemsconsortium/bind9/tags
[13]: https://gitlab.isc.org/isc-projects/bind9-docker/-/tree/v9.21?ref_type=heads
