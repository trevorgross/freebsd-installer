# FreeBSD Installer

Create an ISO for an unattended FreeBSD installation. Optionally install Apache Guacamole, Mediawiki, or Unifi controller. 

Each option creates its own ISO. ISOs are identical except for the argument to the setup script. This was a choice so setup could be completely unattended.

The created ISO is _UEFI only_. I tried for a long time to figure out a hybrid MBR ISO, but when I saw the stock FreeBSD 14 disc doesn't boot with legacy SeaBIOS either I gave up.

Designed for use in a VM. I use qemu/KVM but any with a UEFI bios should work.

## Usage

First, download the [FreeBSD 14.0 DVD](https://download.freebsd.org/releases/amd64/amd64/ISO-IMAGES/14.0/) into the same directory as these files.

Run `./makedist.sh` with one of either `base`, `guac`, `unifi`, or `wiki` as an argument.

Boot from the ISO that's created. 

All three options update the installation and all packages. 

- "base" doesn't install any software packages except sudo, zsh, and readline.
- "guac" installs and configures Apache Guacamole. On reboot, access it at http://<ip>:8080, default username/password both "guacadmin"
- "unifi" installs and configures the Unifi controller software to control Unifi APs, cameras, etc. On reboot, access it at https://<ip>:8443.
- "wiki" installs and configures a Mediawiki wiki with an sqlite database. Cite and MobileFrontend extensions are enabled, short URLs are enabled, and uploads are allowed. On reboot, access it at http://<ip>
    - You should set the SERVER variable in the install script. Use an IP if DNS isn't set up to resolve the created machine.

