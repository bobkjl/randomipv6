#!/bin/bash
count=0
mark=1
cmd_ip="/sbin/ip"
cmd_ip6tables="/sbin/ip6tables"
sleeptime="1s"

if [ -x "$(command -v bc)" ]; then
	echo "bc is installed"
else
	echo "Install bc"
	yum -y install bc || apt install bc -y
fi

GenerateAddress() {
	array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
	ipa=${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}
	ipb=${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}
	ipc=${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}
	ipd=${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}
	echo $Prefix:$ipa:$ipb:$ipc:$ipd
}

add_ipv6() {
	ip=$(GenerateAddress)
	echo "[+] add ip$mark $ip/64"
	p=$(echo "scale=2; 1/($Num-$mark+1)" | bc)
	$cmd_ip -6 addr add $ip/64 dev $Interface && $cmd_ip6tables -t nat -I POSTROUTING $mark -m state --state NEW -p tcp -m multiport --dports http,https -o $Interface -m statistic --mode random --probability $p -j SNAT --to-source $ip
	((mark++))
	if [[ $mark -gt $Num ]]; then
		mark=1
	fi
}

replace_use() {
	get_id=$(ip6tables -t nat -nv -L POSTROUTING --line-number | awk -F 'SNAT' '{print $1}' | grep -v "Chain" | grep -v "num" | awk '{if ($2>=3||$3>=1000) print $1}')
	for use_id in $get_id; do
		rmip=$(ip6tables -t nat -n -L POSTROUTING $use_id | awk -F 'to:' '{print $2}')
		echo "[-] del ip$use_id $rmip/64"
		$cmd_ip -6 addr del $rmip/64 dev $Interface && $cmd_ip6tables -t nat -D POSTROUTING $use_id
		ip=$(GenerateAddress)
		echo "[+] add ip$use_id $ip/64"
		p=$(echo "scale=2; 1/($Num-$use_id+1)" | bc)
		$cmd_ip -6 addr add $ip/64 dev $Interface && $cmd_ip6tables -t nat -I POSTROUTING $use_id -m state --state NEW -p tcp -m multiport --dports http,https -o $Interface -m statistic --mode random --probability $p -j SNAT --to-source $ip
	done
}

read_config() {
	Interface=$(sed '/^Interface=/!d; s/.*=//' /etc/rangeipv6.conf)
	Prefix=$(sed '/^Prefix=/!d; s/.*=//' /etc/rangeipv6.conf)
	Gateway=$(sed '/^Gateway=/!d; s/.*=//' /etc/rangeipv6.conf)
	Num=$(sed '/^Num=/!d; s/.*=//' /etc/rangeipv6.conf)
}

read_config
$cmd_ip -6 addr flush dev $Interface
$cmd_ip6tables -F -t nat
$cmd_ip -6 route add default via $Gateway dev $Interface
while true; do
	while (($count < $Num)); do
		add_ipv6
		((count++))
	done
	replace_use
	sleep $sleeptime
done
