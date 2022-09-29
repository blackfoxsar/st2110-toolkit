# ST 2110 software toolkit

Auteur: PK

This toolkit provides scripts and config to test, monitor and transcode SMPTE ST 2110 streams.
Features:

* capture ST 2110 streams
* transcode ST 2110 to h264 given a SDP (Session Description Protocol)
* integration recipe to create a live version of [EBU-LIST](https://tech.ebu.ch/list)
* misc pcap tools
* analyse stream content like PTP clock

Sponsored by:

![logo](https://site-cbc.radio-canada.ca/site/annual-reports/2014-2015/_images/about/services/cbc-radio-canada.png)

Tested distros:
* Centos 7
* Dockerized Centos 7
* Ubuntu > 20.04

## Install

Install everything (tools, FFmpeg and all the dependencies) using the install scrip:

```sh
$ ./install.sh
Usage: ./install.sh <section>
sections are:
    * common:       compile tools, network utilities, config
    * ptp:          linuxptp
    * transcoder:   ffmpeg, x264, mp3 and other codecs
    * capture:      dpdk-based capture engine
    * ebulist:      EBU-LIST pcap analyzer
    * nmos:         Sony nmos-cpp (deprecated)
```

## Configuration

Both capture and transcoder scripts have default parameters but they can
be overriden by a config file to be installed as `/etc/st2110.conf`.
See the [sample](./config/st2110.conf). This config also provisions an
EBU-LIST server in live mode, i.e. connected to a ST 2110 network.

## Capture

These [instructions](https://github.com/pkeroulas/st2110-toolkit/blob/master/capture/README.md)
show how to setup a performant stream capture engine based on Nvidia/Mellanox NIC + DPDK.

## Transcode

It is required to go through the capture process before in order to
validate all the underlying layers that fowards a stream to an application.
Then one can use our FFmpeg-based transcoder following this [instructions.](https://github.com/pkeroulas/st2110-toolkit/blob/master/transcoder/README.md)

## EBU-LIST

[Integration guide](https://github.com/pkeroulas/st2110-toolkit/blob/master/ebu-list/README.md) for a complete capture and analysis system.

## NMOS

[README](https://github.com/pkeroulas/st2110-toolkit/blob/master/nmos/README.md) shows a POC for a NMOSisfied transcoder.

## Pcap tools

[Pcap script folder](https://github.com/pkeroulas/st2110-toolkit/blob/master/pcap) contains helper scripts which operate on PCAP files:

* ancillary editor: insert different types of failure in SMPTE ST 291-1 payload
* pkt drop detector: count packets and drops for every (src/dst) IP pair found in a given pcap file
* video yuv extractor: convert RFC4175 payload into raw YUV file

Dependencies:

* python 3
* [scapy](https://scapy.net/)
* [bitstruct](https://pypi.org/project/bitstruct/)

## Todos

* deal with transcoder Dockerfile
*nanoseconds ebu-list: fix ptp lock test
    "The rms value reported by ptp4l once the slave has locked with the GM shows the root mean square of the time offset between the PHC and the GM clock. If ptp4l consistently reports rms lower than 100 ns, the PHC is synchronized."
    check_clock.c
* rework`./capture/nic_setup.sh`
* nmos-poller: display ffmpeg status

## [Troubleshoot](./doc/troubleshoot.md)

## Additional resources

* [video](https://github.com/FOXNEOAdvancedTechnology/smpte2110-20-dissector)
* [ancillary](https://github.com/FOXNEOAdvancedTechnology/smpte2110-40-dissector)
* [EBU tools](https://github.com/ebu/smpte2110-analyzer)
