FROM alpine:edge AS bootstrap

# Set up the bootstrap tree
COPY /bootstrap /

# Set up the initial rootfs tree
COPY /rootfs /rootfs

# Set up pacman
RUN apk add arch-install-scripts pacman-makepkg curl zstd && \
    cp -r /rootfs/etc/pacman.d /etc/ && \
    cp /rootfs/etc/pacman.conf /etc/pacman.conf && \
    mkdir /tmp/archlinux-keyring && \
    curl -L https://archlinux.org/packages/core/any/archlinux-keyring/download | unzstd | tar -C /tmp/archlinux-keyring -xv && \
	mv /tmp/archlinux-keyring/usr/share/pacman/keyrings /usr/share/pacman/

# Install the base packages
RUN pacman-key --init && pacman-key --populate
RUN chmod +x /usr/local/bin/pacstrap-docker && pacstrap-docker /rootfs base

# AUR prebuilts
FROM ghcr.io/beakthoven/docker-images:arch-devel AS build-aur
WORKDIR /home/auruser
USER auruser
RUN git clone https://aur.archlinux.org/paru-bin.git paru && \
    cd paru && makepkg -s --noconfirm

RUN mkdir -p /home/auruser/alhp && \
    cd /home/auruser/alhp && \
    git clone https://aur.archlinux.org/alhp-keyring.git && \
    git clone https://aur.archlinux.org/alhp-mirrorlist.git && \
    cd alhp-keyring && makepkg -s --skippgpcheck --noconfirm && cd .. && \
    cd alhp-mirrorlist && makepkg -s --noconfirm

WORKDIR /
USER root
RUN ls -l /home/auruser/paru && ls -l /home/auruser/alhp/*
RUN mkdir -p /build/alhp
RUN rm -f /home/auruser/paru/*-debug-*.pkg.tar.zst && \
    mv /home/auruser/paru/*.pkg.tar.zst /build/ && \
    mv /home/auruser/alhp/*/*.pkg.tar.zst /build/alhp/
RUN ls -l /build/alhp/ && \
    ls -l /build/



#################
# Minimal image #
#################
FROM scratch as arch

# Copy the bootstrapped rootfs
COPY --from=bootstrap /rootfs /

# Set up locale and timezone
ENV LANG=en_US.UTF-8
RUN locale-gen
ENV TZ="Asia/Kolkata"
RUN ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime

# Pacman
RUN pacman-key --init && \
    pacman-key --populate

# Packages for our use (Update mirrorlist to get new packages before ALHP)
RUN pacman -Syy --noconfirm
RUN cat /etc/minimal_packages.txt | xargs pacman -S --noconfirm
RUN reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
RUN pacman -Syyu --noconfirm

# Install prebuilt paru
COPY --from=build-aur /build/paru-*.pkg.tar.zst /tmp/paru.pkg.tar.zst
RUN pacman -U /tmp/paru.pkg.tar.zst --noconfirm && rm /tmp/paru.pkg.tar.zst

# Setup auruser (for paru)
RUN useradd -m auruser && \
    echo 'auruser ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# ALHP installation
COPY --from=build-aur /build/alhp/*.pkg.tar.zst /tmp/alhp/
RUN pacman -U /tmp/alhp/*.pkg.tar.zst --noconfirm && rm -rf /tmp/alhp
RUN paru -Sccd --noconfirm

# ALHP mirrorlist setup
RUN sed -i "/\[core-x86-64-v3\]/,/Include/"'s/^#//' /etc/pacman.conf
RUN sed -i "/\[extra-x86-64-v3\]/,/Include/"'s/^#//' /etc/pacman.conf
RUN pacman -Syy --noconfirm

# Remove unwanted and update
RUN pacman -R reflector rsync --noconfirm
RUN pacman -Qdtq | xargs -r pacman -Rns --noconfirm
RUN pacman -Syyu --noconfirm

# Cleanup
RUN rm -rf /var/lib/pacman/sync/* && rm -rf /etc/minimal_packages.txt && rm -rf /etc/devel_packages.txt && rm -rf /tmp/*

# Set up pacman-key without distributing the lsign key
# See https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/301942f9e5995770cb5e4dedb4fe9166afa4806d/README.md#principles
# Source: https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/301942f9e5995770cb5e4dedb4fe9166afa4806d/Makefile#L22
RUN bash -c "rm -rf etc/pacman.d/gnupg/{openpgp-revocs.d/,private-keys-v1.d/,pubring.gpg~,gnupg.S.}*"

CMD ["/usr/bin/bash"]

###############
# Devel image #
###############
FROM scratch as arch-devel

# Copy the bootstrapped rootfs
COPY --from=bootstrap /rootfs /

# Set up locale and timezone
ENV LANG=en_US.UTF-8
RUN locale-gen
ENV TZ="Asia/Kolkata"
RUN ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime

# Pacman
RUN pacman-key --init && \
    pacman-key --populate

# Packages for our use (Update mirrorlist to get new packages before ALHP)
RUN pacman -Syy --noconfirm && pacman -S base-devel --noconfirm
RUN cat /etc/minimal_packages.txt | xargs pacman -S --noconfirm
RUN reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
RUN pacman -Syyu --noconfirm

# Install prebuilt paru
COPY --from=build-aur /build/paru-*.pkg.tar.zst /tmp/paru.pkg.tar.zst
RUN pacman -U /tmp/paru.pkg.tar.zst --noconfirm && rm /tmp/paru.pkg.tar.zst

# Setup auruser (for paru)
RUN useradd -m auruser && \
    echo 'auruser ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# AHLP installation
COPY --from=build-aur /build/alhp/*.pkg.tar.zst /tmp/alhp/
RUN pacman -U /tmp/alhp/*.pkg.tar.zst --noconfirm && rm -rf /tmp/alhp
RUN paru -Sccd --noconfirm

# ALHP mirrorlist setup
RUN sed -i "/\[core-x86-64-v3\]/,/Include/"'s/^#//' /etc/pacman.conf
RUN sed -i "/\[extra-x86-64-v3\]/,/Include/"'s/^#//' /etc/pacman.conf
RUN pacman -Syyu --noconfirm

# Devel packages
RUN cat /etc/devel_packages.txt | xargs pacman -S --noconfirm

# Cleanup
RUN rm -rf /var/lib/pacman/sync/* && rm -rf /etc/minimal_packages.txt && rm -rf /etc/devel_packages.txt && rm -rf /tmp/*

# Perl path
ENV PATH="/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl:$PATH"

# Test python and pip
RUN python --version && pip --version

# Set up pacman-key without distributing the lsign key
# See https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/301942f9e5995770cb5e4dedb4fe9166afa4806d/README.md#principles
# Source: https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/301942f9e5995770cb5e4dedb4fe9166afa4806d/Makefile#L22
RUN bash -c "rm -rf etc/pacman.d/gnupg/{openpgp-revocs.d/,private-keys-v1.d/,pubring.gpg~,gnupg.S.}*"

CMD ["/usr/bin/bash"]
