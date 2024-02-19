# nix flake for VU-Server

This repository contains a Nix flake packaging [VU-Server], the host software for controlling [Streacom VU-1 dials].

## usage as a flake

[![FlakeHub](https://img.shields.io/endpoint?url=https://flakehub.com/f/mycoliza/vu-server/badge)](https://flakehub.com/flake/mycoliza/vu-server)

Add vu-server-flake to your `flake.nix`:

```nix
{
  inputs.vu-server.url = "https://flakehub.com/f/mycoliza/vu-server/*.tar.gz";

  outputs = { self, vu-server }: {
    # Use in your outputs
  };
}

```

[VU-Server]: https://github.com/SasaKaranovic/VU-Server
[Streacom VU-1 dials]: https://streacom.com/products/vu1-dynamic-analogue-dials/
