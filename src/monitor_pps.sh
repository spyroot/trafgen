#!/bin/bash
# Scripts read stats inside a pod at sample time (1 second default) rate.
# note if we need speed this we can write small C code that read that stats.
# On rx and tx we can run this script to sample TX/RX and all other stats.
# tuple serialize as comma separate value later passed to numpy hence vectorized
# do cross correlation.
#
# Mus mbayramov@vmware.com
INTERVAL="1"

display_help() {
    echo "Usage: $0 -i <interface> [-d <direction>] [-c <core>]"
    echo "-i: Specify network interface (required)"
    echo "-d: Direction to monitor (tx, rx, or tuple), default is empty (monitor mode)"
    echo "-c: CPU core to monitor, default is 0"
    echo "-s: Sample time in seconds, default is 1"
}


#sar -u ALL -P ALL 1
#tuna --show_irqs

IF="eth0"
DIRECTION=""
CPU_CORE=0

while getopts ":i:d:c:h" opt; do
    case ${opt} in
        i)
            IF=$OPTARG
            ;;
        d)
            DIRECTION=$OPTARG
            ;;
        c)
            CPU_CORE=$OPTARG
            if [[ "$CPU_CORE" =~ "-" ]]; then
                CPU_CORE=${CPU_CORE%-*}
            fi
            ;;
        h)
            display_help
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            display_help
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            display_help
            exit 1
            ;;
    esac
done

TOTAL_CORES=$(grep -c ^processor /proc/cpuinfo)

#if [ "$DIRECTION" != "tx" ] && [ "$DIRECTION" != "rx" ] && [ "$DIRECTION" != "both" ]; then
#    echo "Invalid direction. Please specify 'tx', 'rx', or omit for both."
#    exit 1
#fi

if [ -z "$IF" ] || [ ! -d "/sys/class/net/$IF" ]; then
    echo "Error: Network interface '$IF' is not valid or does not exist." >&2
    display_help
    exit 1
fi

while true; do

  R1=$(cat /sys/class/net/"$IF"/statistics/rx_packets)
  T1=$(cat /sys/class/net/"$IF"/statistics/tx_packets)

  RD1=$(cat /sys/class/net/"$IF"/statistics/rx_dropped)
  TD1=$(cat /sys/class/net/"$IF"/statistics/tx_dropped)

  RB1=$(cat /sys/class/net/"$IF"/statistics/rx_bytes)
  TB1=$(cat /sys/class/net/"$IF"/statistics/tx_bytes)

  RE1=$(cat /sys/class/net/"$IF"/statistics/rx_errors)
  TE1=$(cat /sys/class/net/"$IF"/statistics/tx_errors)

  IRQ2_T1=$(grep '^intr' /proc/stat | awk '{print $2}')
  SIRQ_T1=$(grep '^softirq' /proc/stat | awk '{print $2}')

  NET_TX1=$(awk '/NET_TX/ {sum=0; for(i=2; i<=NF; i++) sum+=$i; print sum}' /proc/softirqs)
  NET_RX1=$(awk '/NET_RX/ {sum=0; for(i=2; i<=NF; i++) sum+=$i; print sum}' /proc/softirqs)

  # reading proc stats
  # cpu0 55742 0 58908 34703769 167 0 16002 0 0 0
  CPU_STATS_1=$(awk "/^cpu$CPU_CORE /" /proc/stat)

  sleep "$INTERVAL"

  R2=$(cat /sys/class/net/"$IF"/statistics/rx_packets)
  T2=$(cat /sys/class/net/"$IF"/statistics/tx_packets)

  RD2=$(cat /sys/class/net/"$IF"/statistics/rx_dropped)
  TD2=$(cat /sys/class/net/"$IF"/statistics/tx_dropped)

  RB2=$(cat /sys/class/net/"$IF"/statistics/rx_bytes)
  TB2=$(cat /sys/class/net/"$IF"/statistics/tx_bytes)

  RE2=$(cat /sys/class/net/"$IF"/statistics/rx_errors)
  TE2=$(cat /sys/class/net/"$IF"/statistics/tx_errors)

  IRQ2_T2=$(grep '^intr' /proc/stat | awk '{print $2}')
  SIRQ_T2=$(grep '^softirq' /proc/stat | awk '{print $2}')

  NET_TX2=$(awk '/NET_TX/ {sum=0; for(i=2; i<=NF; i++) sum+=$i; print sum}' /proc/softirqs)
  NET_RX2=$(awk '/NET_RX/ {sum=0; for(i=2; i<=NF; i++) sum+=$i; print sum}' /proc/softirqs)

  NET_TX_RATE=$((NET_TX2 - NET_TX1))
  NET_RX_RATE=$((NET_RX2 - NET_RX1))

  TX_PPS=$((T2 - T1))
  RX_PPS=$((R2 - R1))

  TX_DROP=$((TD2 - TD1))
  RX_DROP=$((RD2 - RD1))

  TX_ERR=$((TE2 - TE1))
  RX_ERR=$((RE2 - RE1))

  TX_BYTES=$((TB2 - TB1))
  RX_BYTES=$((RB2 - RB1))

  IRQ_RATE=$((IRQ2_T2 - IRQ2_T1))
  S_IRQ_RATE=$((SIRQ_T2 - SIRQ_T1))

  if [ "$TX_PPS" -gt 0 ]; then
    AVG_TX_PACKET_SIZE=$((TX_BYTES / TX_PPS))
  else
    AVG_TX_PACKET_SIZE=0
  fi

  if [ "$RX_PPS" -gt 0 ]; then
    AVG_RX_PACKET_SIZE=$((RX_BYTES / RX_PPS))
  else
    AVG_RX_PACKET_SIZE=0
  fi

  # t2 sample
  # user: normal processes executing in user mode
  # nice: niced processes executing in user mode
  # system: processes executing in kernel mode
  # idle: twiddling thumbs
  # iowait: waiting for I/O to complete
  # irq: servicing interrupts
  # softirq: servicing softirqs
  CPU_STATS_2=$(awk "/^cpu$CPU_CORE /" /proc/stat)
  IDLE_1=$(echo "$CPU_STATS_1" | awk '{print $5}')
  TOTAL_1=$(echo "$CPU_STATS_1" | awk '{sum=0; for (i=2; i<=NF; i++) sum+=$i; print sum}')
  IDLE_2=$(echo "$CPU_STATS_2" | awk '{print $5}')
  TOTAL_2=$(echo "$CPU_STATS_2" | awk '{sum=0; for (i=2; i<=NF; i++) sum+=$i; print sum}')
  IDLE_DELTA=$((IDLE_2 - IDLE_1))
  TOTAL_DELTA=$((TOTAL_2 - TOTAL_1))

  CPU_USAGE=$(((TOTAL_DELTA - IDLE_DELTA) * 100 / TOTAL_DELTA))

  if [ "$DIRECTION" = "tx" ]; then
    echo "rx"
    echo "$TX_PPS"
  elif [ "$DIRECTION" = "rx" ]; then
    echo "$RX_PPS"
  elif [ "$DIRECTION" = "tuple" ]; then
    # collect RX PPS / TX PPS
    echo "$RX_PPS, $TX_PPS, $RX_DROP, $TX_DROP, $RX_ERR, $TX_ERR, $RX_BYTES, $TX_BYTES, $IRQ_RATE, $S_IRQ_RATE, $NET_TX_RATE, $NET_RX_RATE, $CPU_CORE, $CPU_USAGE"
  else
    echo "TX $IF: $TX_PPS pkts/s RX $IF: $RX_PPS pkts/s TX DROP: $TX_DROP pkts/s RX DROP: $RX_DROP pkts/s IRQ Rate: $IRQ_RATE, SIRQ Rate: $S_IRQ_RATE NET_TX_RATE: $NET_TX_RATE, NET_RX_RATE: $NET_RX_RATE AVG_RX_SIZE: $AVG_RX_PACKET_SIZE AVG_TX_SIZE: $AVG_TX_PACKET_SIZE CPU Core $CPU_CORE Usage: $CPU_USAGE%"
  fi

done

