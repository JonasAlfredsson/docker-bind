# docker-bind

A Docker image of the ISC [Bind/Bind9/Named][2] DNS service that has been set
up so it is easy to configure when running inside a container.

There are both Debian and Alpine images available, and they install the server
version available for their respective package manager which means they differ
slightly on the minor version. Useful configuration files and folders from the
Debian image are copied to the Alpine one for a consistent experience across
both.

### Acknowledgments and Thanks

This repository was originally a fork of [ventz/docker-bind][1], but what was
supposed to be just a small pull request turned into a complete rewrite. While
very little of the original code remains it would be dishonest to not keep the
commit history since without it I would not have found inspiration to make my
own version.



# Usage

The amount of options available for Bind is absolutely enormous, and what
options to use will be very different depending on how you intend to run your
instance so I will not even try to list suggestions here. But to just get you
started we will set up a super simple forwarding server, so it becomes easier
to understand what configuration files are needed and where they are expected
to be found.


## Available Environment Variables

> :information_source: It is *possible* to change these environment variables,
  but you will most likely break things.

- `BIND_LOG`: Input argument for configuring stderr or file logging (default: `-f`)
- `BIND_USER`: The username the service will run as (default: alpine=`named`, debian=`bind`)


## Configuration Files

When the container starts it will launch Bind which will read the main config
file `/etc/bind/named.conf`, however, that one has only the following content:

```conf
include "/etc/bind/local-config/named.conf.logging";
include "/etc/bind/local-config/named.conf.options";
include "/etc/bind/local-config/named.conf.local";
```

What this means is that these three files are expected to be present when the
container starts, and some basic (but fully functioning) examples are present
inside the [`example-configs/`](./example-configs/) folder.

### Create `rndc.key`
At the top of the [`named.conf.local`](./example-configs/named.conf.local) file
we include a file which needs to be created manually by you as it should be
unique and secret. You can have the file written to the `example-configs/`
folder by running the following command:

```bash
docker run -it --rm \
    -v $(pwd)/example-configs:/etc/bind/local-config \
    --entrypoint=/bin/sh \
    jonasal/bind:9 \
    -c 'rndc-confgen -a -A hmac-sha256 -b 256 -u "${BIND_USER}" -c /etc/bind/local-config/rndc.key'
```

## Volumes

There are two locations that are important for this image, and the first one
is `/etc/bind/local-config/` since that is the place where it expects to find
your custom configuration files. It should be very difficult to miss as the
image wont start without this folder properly populated.

The other important location is the working directory of the server that is
defined at the top of the
[`named.conf.options`](./example-configs/named.conf.options) file. This is the
location where your primary zone files are expected to be found and to where
slave zone files will be written, so for persistence I recommend to host mount
this folder and make sure Bind is allowed to write to it:

```bash
mkdir zones && sudo chown root:101 zones && sudo chmod 775 zones
```

While you could change it to anything you want the examples below expects it to
remain as it is now.

### Custom Entrypoint Scripts
There is a third location that might be of interest and that is the folder
`/entrypoint.d/` since the main [`entrypoint.sh`](./entrypoint.sh) will look
inside this folder for any files ending with `.sh` and try to execute them in
alphabetical order. This allows you to run custom commands before the Bind
service is started.

## Input Arguments

Any extra input arguments provided as the `command`, when starting the image,
will be appended directly to the Bind service. Please take a look at the last
line in [`entrypoint.sh`](./entrypoint.sh) to see how it works.



## Run

After you have read through all the steps above we can finally start the
image:


```bash
docker run -it --rm \
    -p 54:53 -p 54:53/udp \
    -v $(pwd)/example-configs:/etc/bind/local-config
    -v $(pwd)/zones:/var/cache/bind
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
will be printed unless the flag is provided.

### Verify

In order to verify that Bind works, after running the command above, is to
just make a quick query to your machine on port 54 and see if anything is
printed in the container logs.

```bash
dig @127.0.0.1 -p 54 google.se
```

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






[1]: https://github.com/ventz/docker-bind
[2]: https://www.isc.org/bind/
[3]: https://www.freedesktop.org/software/systemd/man/systemd-resolved.service.html
[4]: https://askubuntu.com/a/907249
