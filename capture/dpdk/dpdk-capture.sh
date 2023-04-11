#!/bin/bash

usage(){
    echo "$0 interprets tcpdump-like parameters and passes them to
    dpdk utilties, i.e. dpdk-testpmd and dpdk-pdump. It also sends IGMP
    requests (requires sudo) when a filter expression is given.
Usage:
    $0 -i interface0 [-i interface1] -w file.pcap [-G <secondes>] [-v|V] [ filter expr ]
        -i  Network interface(s), be aware that dpdk captures everything, ptp included.
        -w  Output pcap file
        -G  Capture duration
        -v  Verbose
        -V  Very verbose
        filter expression tcpdump-like expression, but only for multicast to be subscribed by IGMP

Exples:
    $0 -i enp1s0f0 -w /tmp/single.pcap -G 1 dst 225.192.10.1 or dst 225.192.10.2
    $0 -V -i enp1s0f0 -i enp1s0f1 -w /tmp/dual.pcap -G 1 # dual port means that local ptp slave won't see ptp traffic
    " >&2
}

duration=2
verbose=0
dual_port=0
testpmd_log=/tmp/dpdk-testpmd.log
iface=""

dpdk_log(){
    echo "dpdk-capture: $@"
}

if ps aux | grep -q [p]dump; then
   dpdk_log "dpdk-pdump is already in use, exit."
   exit 2
fi

dpdk_log "Parse args: ------------------------------------------ "

#  typical cmdline to be translated:
#  $ tcpdump -i interfaceName --time-stamp-precision=nano \
#   -j adapter_unsynced\--snapshot-length=N -v -w pcap -G 2 -W 1 \
#   dst 192.168.1.1 or dst 192.168.1.2
while getopts ":i:w:G:W:vV" o; do
    case "${o}" in
        i | interface)
            if [ ! -z "$iface" ]; then
                dual_port=1
            fi

            iface="$iface ${OPTARG}"
            ;;
        j)
            ;;
        #-)
        #    case ${OPTARG} in
        #        time-stamp-precision*)
        #            ;;
        #        snapshot-length*)
        #            ;;
        #    esac
        #    ;;
        w)
            output=${OPTARG}
            ;;
        G)
            duration=${OPTARG}
            ;;
        W)
            #ignore file number
            ;;
        v)
            verbose=1
            ;;
        V)
            set -x
            verbose=1
            ;;
        *)
            dpdk_log  "unsupported option ${o}"
            usage
            exit 1
            ;;
    esac
done

shift $((OPTIND-1))

if [ -z "$iface" -o -z "$output" ]; then
    dpdk_log "Missing argument"
    usage
    exit 1
fi

filter=$@
IPs=$(echo $filter | sed 's/dst//g; s/or//g' | tr -s ' ' '\n')
pcap=/tmp/dpdk/output

dpdk_log "
iface: $iface
pcap: $output
filter: $filter
dual_port: $dual_port
duration: $duration"


dpdk_log "Checking interface: $i ------------------------------------------ "

pci=""
for i in $iface; do
    if [ ! -d /sys/class/net/$i ]; then
        dpdk_log "$i doesn\'t exist, exit."
        exit 1
    fi
    if [ $(cat /sys/class/net/$i/operstate) != "up" ]; then
        dpdk_log "$i is not up, exit."
        exit 1
    fi
    pci="$pci -w $(dpdk-devbind --status | grep "if=$i" | cut -d ' ' -f1)"
done

dpdk_log "Joining mcast: $IPs ------------------------------------------ "
for i in $iface; do
    if [ ! -z "$filter" ]; then

        if ! smcroutectl show > /dev/null; then
            smcrouted
        fi

        for ip in $IPs; do
            smcroutectl join $i $ip
            if ! netstat -ng | grep -q "$i.*$ip"; then
                dpdk_log "Can\'t joint $ip"
            fi
        done

        if [ $verbose -eq 1 ]; then
            netstat -ng | grep $i
        fi
    else
        dpdk_log "No filter"
    fi
done

if [ $dual_port -eq 1 ]; then
    dpdk_log "Pausing PTP------------------------------------------"
    # prevent linuxptp from interfering with the timestamping
    /etc/init.d/ptp stop
fi

# dpdk
dpdk_log "Capturing------------------------------------------"

if ps aux | grep -q [t]estpmd; then
    dpdk_log "PMD already up"
else
    dpdk_log "Start PMD"
    # create a detached session to run PMD server
    screen -dmS testpmd -L -Logfile $testpmd_log \
        dpdk-testpmd -l 0-3 -n 4 -- --enable-rx-timestamp --forward-mode=rxonly --portmask=0x3

    sleep 3
fi

# filter out ptp
# testpmd must be in --interactive
#screen -S testpmd -X stuff "bpf-load rx 0 0 J /tmp/bpf_no_ptp.o
#start
#"

#pkt_rx_start=$(ethtool -S $i | grep rx_packets: | sed  's/.*: \(.*\)/\1/')
#pkt_drop_start=$(ethtool -S $i | grep rx_out_of_buffer: | sed  's/.*: \(.*\)/\1/')

#dpdk-dumpcap -a duration:$duration -w pcap-$port.pcap -i 0 -i 1 # doesn't work better

dpdk_log "Start pdump"
if [ $dual_port -eq 1 ]; then
    args="-- --pdump port=0,queue=0,rx-dev=$pcap-0.pcap --pdump port=1,queue=0,rx-dev=$pcap-1.pcap"
else
    port=$(echo $iface | sed 's/.*\(.\)/\1/')
    args="-- --pdump port=$port,queue=*,rx-dev=$pcap-$port.pcap"
fi
dpdk-pdump $args 2>&1 &

sleep $duration

dpdk_log "Stop testpmd / pdump -------------------------------------"
# send a SGINT after after duration
killall -s 2 dpdk-pdump

# send carriage return to stop testpmd
screen -S testpmd -X stuff "
"
if [ $verbose -eq 1 ]; then
    cat $testpmd_log
fi
rm $testpmd_log

if [ $dual_port -eq 1 ]; then
    dpdk_log "Resuming PTP: $ptp_cmd -------------------------------------"
    /etc/init.d/ptp start
fi

for i in $iface; do
    if [ ! -z "$filter" ]; then
        dpdk_log "Leaving mcast ------------------------------------------"
        for ip in $IPs; do
            smcroutectl leave $i $ip
        done
    fi

    port=$(echo $i | sed 's/.*\(.\)/\1/')
    if [ ! -f $pcap-$port.pcap  ]; then
        dpdk_log "File not found: $pcap-$port.pcap"
        exit 1
    fi

    if [ $verbose -eq 1 ]; then
        dpdk_log "pcapinfo port $port"
        capinfos $pcap-$port.pcap
    fi
done

#pkt_rx_end=$(ethtool -S $i | grep rx_packets: | sed  's/.*: \(.*\)/\1/')
#pkt_drop_end=$(ethtool -S $i | grep rx_out_of_buffer: | sed  's/.*: \(.*\)/\1/')
#dpdk_log "rx: $(echo "$pkt_rx_end - $pkt_rx_start" | bc)"
#dpdk_log "drop: $(echo "$pkt_drop_end - $pkt_drop_start" | bc)"

if [ $dual_port -eq 1 ]; then
    mergecap -w $output -F nsecpcap $pcap-0.pcap $pcap-1.pcap
    echo $(ls $pcap-[01].pcap) merged into $output
    #rm -f $pcap-0.pcap $pcap-1.pcap
else
    port=$(echo $iface | sed 's/.*\(.\)/\1/')
    mv $pcap-$port.pcap $output
    echo "PCAP: $output"
fi

chmod 666 $output
