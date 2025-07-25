#!/bin/sh

PROG="$(nvram get zerotier_bin)"
config_path="/etc/storage/zerotier-one"
user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
github_proxys="$(nvram get github_proxy)"
[ -z "$github_proxys" ] && github_proxys=" "
scriptfilepath=$(cd "$(dirname "$0")"; pwd)/$(basename $0)
zerotier_renum=`nvram get zerotier_renum`

zt_restart () {
relock="/var/lock/zerotier_restart.lock"
if [ "$1" = "o" ] ; then
	nvram set zerotier_renum="0"
	[ -f $relock ] && rm -f $relock
	return 0
fi
if [ "$1" = "x" ] ; then
	zerotier_renum=${zerotier_renum:-"0"}
	zerotier_renum=`expr $zerotier_renum + 1`
	nvram set zerotier_renum="$zerotier_renum"
	if [ "$zerotier_renum" -gt "3" ] ; then
		I=19
		echo $I > $relock
		logger -t "【zerotier】" "多次尝试启动失败，等待【"`cat $relock`"分钟】后自动尝试重新启动"
		while [ $I -gt 0 ]; do
			I=$(($I - 1))
			echo $I > $relock
			sleep 60
			[ "$(nvram get zerotier_renum)" = "0" ] && break
   			#[ "$(nvram get zerotier_enable)" = "0" ] && exit 0
			[ $I -lt 0 ] && break
		done
		nvram set zerotier_renum="1"
	fi
	[ -f $relock ] && rm -f $relock
fi
start_zero
}

start_instance() {
	port="$(nvram get zerotier_port)"
	args="$(nvram get zerotier_args)"
	nwid="$(nvram get zerotier_id)"
	moonid="$(nvram get zerotier_moonid)"
	secret="$(nvram get zerotier_secret)"
	[ -d "$config_path/networks.d" ] || mkdir -p $config_path/networks.d
	[ -d "$config_path/moons.d" ] || mkdir -p "$config_path/moons.d"
	if [ -n "$port" ]; then
		args="$args -p$port"
	fi
 	if [ ! -z "$nwid" ] ; then
		[ ! -f "$config_path/networks.d/$nwid.conf" ] && touch $config_path/networks.d/$nwid.conf
  	else
		logger -t "【zerotier】" "ZeroTier 网络ID为空，请正确填写！"
   	fi
 	if [ -s "$config_path/identity.secret" ] ; then
		secret="$(cat $config_path/identity.secret)"
  	fi
  	if [ ! -s "$config_path/identity.secret" ] ; then
  		if [ ! -z "$secret" ] ; then
  			logger -t "【zerotier】" "${config_path}/identity.secret密匙文件为空,找到密匙,正在写入到文件,请稍后..."
  			echo "$secret" >$config_path/identity.secret
  		else
  			logger -t "【zerotier】" "密匙为空,正在生成密匙和文件,请稍后..."
  			sf="$config_path/identity.secret"
  			pf="$config_path/identity.public"
  			$PROGIDT generate "$sf" "$pf"  >/dev/null
  			[ $? -ne 0 ] && return 1
  			secret="$(cat $sf)"
  			nvram set zerotier_secret="$secret"
  			nvram commit
  		fi
  	
  	fi
  	if [ ! -s "$config_path/identity.public" ] ; then
  		logger -t "【zerotier】" "${config_path}/identity.public公匙文件为空,正在生成公匙文件,请稍后..."
  		$PROGIDT getpublic $config_path/identity.secret >$config_path/identity.public

  	fi
   	mkdir -p /tmp/zero/peers.d
    	if [ ! -L /etc/storage/zerotier-one/peers.d ] ; then
     		rm -rf /etc/storage/zerotier-one/peers.d
		ln -sf /tmp/zero/peers.d /etc/storage/zerotier-one/peers.d
     	fi
      	mkdir -p /tmp/zero/controller.d
    	if [ ! -L /etc/storage/zerotier-one/controller.d ] ; then
     		rm -rf /etc/storage/zerotier-one/controller.d
		ln -sf /tmp/zero/controller.d /etc/storage/zerotier-one/controller.d
     	fi
      	touch /tmp/zero/zerotier-one.port
    	if [ ! -L /etc/storage/zerotier-one/zerotier-one.port ] ; then
     		rm -rf /etc/storage/zerotier-one/zerotier-one.port
		ln -sf /tmp/zero/zerotier-one.port /etc/storage/zerotier-one/zerotier-one.port
     	fi
      	touch /tmp/zero/zerotier-one.pid
    	if [ ! -L /etc/storage/zerotier-one/zerotier-one.pid ] ; then
     		rm -rf /etc/storage/zerotier-one/zerotier-one.pid
		ln -sf /tmp/zero/zerotier-one.pid /etc/storage/zerotier-one/zerotier-one.pid
     	fi
      	touch /tmp/zero/metrics.prom
    	if [ ! -L /etc/storage/zerotier-one/metrics.prom ] ; then
     		rm -rf /etc/storage/zerotier-one/metrics.prom
		ln -sf /tmp/zero/metrics.prom /etc/storage/zerotier-one/metrics.prom
     	fi
	logger -t "【zerotier】" "启动 $PROG $args $config_path"
	$PROG $args $config_path >/dev/null 2>&1 &

	while [ ! -f $config_path/zerotier-one.port ]; do
		sleep 1
	done
	if [ -n "$moonid" ]; then
		$PROGCLI orbit $moonid $moonid
		logger -t "【zerotier】" "加入moon: $moonid 成功!"
	fi
	if [ -n "$nwid" ]; then
		$PROGCLI join $nwid
		logger -t "【zerotier】" "加入网络: $nwid 成功!"
		rules

	fi
}

zt_keep() {
	logger -t "【zerotier】" "守护进程启动"
	if [ -s /tmp/script/_opt_script_check ]; then
	sed -Ei '/【zerotier】|^$/d' /tmp/script/_opt_script_check
	zt0=$(ifconfig | grep zt | awk '{print $1}')
	cat >> "/tmp/script/_opt_script_check" <<-OSC
	[ -z "\`pidof zerotier-one\`" ] && logger -t "进程守护" "zerotier-one 进程掉线" && eval "$scriptfilepath start &" && sed -Ei '/【zerotier】|^$/d' /tmp/script/_opt_script_check #【zerotier】
	[ -z "\$(iptables -L -n -v | grep '$zt0')" ] && logger -t "进程守护" "zerotier-one 防火墙规则失效" && eval "$scriptfilepath start &" && sed -Ei '/【zerotier】|^$/d' /tmp/script/_opt_script_check #【zerotier】
	OSC

	fi

exit 0
}

rules() {
	while [ "$(ifconfig | grep zt | awk '{print $1}')" = "" ]; do
		sleep 1
	done
	nat_enable=$(nvram get zerotier_nat)
	zt0=$(ifconfig | grep zt | awk '{print $1}')
	del_rules
 	logger -t "【zerotier】" "添加${zt0}防火墙规则中..."
	iptables -I INPUT -i $zt0 -j ACCEPT
	iptables -I FORWARD -i $zt0 -o $zt0 -j ACCEPT
	iptables -I FORWARD -i $zt0 -j ACCEPT
	if [ $nat_enable -eq 1 ]; then
		iptables -t nat -I POSTROUTING -o $zt0 -j MASQUERADE
		while [ "$(ip route | grep -E "dev\s+$zt0\s+proto\s+kernel"| awk '{print $1}')" = "" ]; do
		    sleep 1
		done
		ip_segment=$(ip route | grep -E "dev\s+$zt0\s+proto\s+kernel"| awk '{print $1}')
                logger -t "【zerotier】" "将 $zt0 网段 $ip_segment 添加进NAT规则中..."
		iptables -t nat -I POSTROUTING -s $ip_segment -j MASQUERADE
		zero_route "add"
	fi
	if [ ! -z "`pidof zerotier-one`" ] ; then
 		mem=$(cat /proc/$(pidof zerotier-one)/status | grep -w VmRSS | awk '{printf "%.1f MB", $2/1024}')
   		cpui="$(top -b -n1 | grep -E "$(pidof zerotier-one)" 2>/dev/null| grep -v grep | awk '{for (i=1;i<=NF;i++) {if ($i ~ /zerotier-one/) break; else cpu=i}} END {print $cpu}')"
 		logger -t "【zerotier】" "zerotier-one ${zt_ver}启动成功! "
   		logger -t "【zerotier】" "内存占用 ${mem} CPU占用 ${cpui}%"
   		zt_restart o
   	fi
 	[ -z "`pidof zerotier-one`" ] && logger -t "【zerotier】" "启动失败, 注意检查${PROG}是否下载完整,10 秒后自动尝试重新启动" && sleep 10 && zt_restart x
 	count=0
        while [ $count -lt 5 ]
        do
       ztstatus=$($PROGCLI info | awk '{print $5}')
       if [ "$ztstatus" = "OFFLINE" ]; then
	        sleep 2
        elif [ "$ztstatus" = "ONLINE" ]; then
        	ztid=$($PROGCLI info | awk '{print $3}')
        	nvram set zerotierdev_id=$ztid
        	nvram set zerotier_status="${ztstatus} 在线"
        	break
        fi
        count=$(expr $count + 1)
        done
	if [ "$($PROGCLI info | awk '{print $5}')" = "OFFLINE" ] ; then
	  logger -t "【zerotier】" "当前zerotier未上线，可能你的网络无法链接到zerotier官方服务器！"
	  nvram set zerotier_status="OFFLINE 离线"
          exit 1
        fi
        zt_keep
}

del_rules() {
	zt0=$(ifconfig | grep zt | awk '{print $1}')
	ip_segment=$(ip route | grep -E "dev\s+$zt0\s+proto\s+kernel"| awk '{print $1}')
	#logger -t "【zerotier】" "删除${zt0}防火墙规则中..."
	iptables -D INPUT -i $zt0 -j ACCEPT 2>/dev/null
	iptables -D FORWARD -i $zt0 -o $zt0 -j ACCEPT 2>/dev/null
	iptables -D FORWARD -i $zt0 -j ACCEPT 2>/dev/null
	iptables -t nat -D POSTROUTING -o $zt0 -j MASQUERADE 2>/dev/null
	iptables -t nat -D POSTROUTING -s $ip_segment -j MASQUERADE 2>/dev/null
}

zero_route(){
	rulesnum=`nvram get zero_staticnum_x`
	for i in $(seq 1 $rulesnum)
	do
		j=`expr $i - 1`
		route_enable=`nvram get zero_enable_x$j`
		zero_ip=`nvram get zero_ip_x$j`
		zero_route=`nvram get zero_route_x$j`
		if [ "$1" = "add" ]; then
			if [ $route_enable -ne 0 ]; then
				ip route add $zero_ip via $zero_route dev $zt0
				echo "$zt0"
			fi
		else
			ip route del $zero_ip via $zero_route dev $zt0
		fi
	done
}

get_zttag() {
	curltest=`which curl`
	logger -t "【zerotier】" "开始获取最新版本..."
    	if [ -z "$curltest" ] || [ ! -s "`which curl`" ] ; then
      		tag="$( wget --no-check-certificate -T 5 -t 3 --user-agent "$user_agent" --max-redirect=0 --output-document=-  https://api.github.com/repos/lmq8267/ZeroTierOne/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4 )"
	 	[ -z "$tag" ] && tag="$( wget --no-check-certificate -T 5 -t 3 --user-agent "$user_agent" --quiet --output-document=-  https://api.github.com/repos/lmq8267/ZeroTierOne/releases/latest  2>&1 | grep 'tag_name' | cut -d\" -f4 )"
    	else
      		tag="$( curl -k --connect-timeout 3 --user-agent "$user_agent"  https://api.github.com/repos/lmq8267/ZeroTierOne/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4 )"
       	[ -z "$tag" ] && tag="$( curl -Lk --connect-timeout 3 --user-agent "$user_agent" -s  https://api.github.com/repos/lmq8267/ZeroTierOne/releases/latest  2>&1 | grep 'tag_name' | cut -d\" -f4 )"
        fi
	[ -z "$tag" ] && logger -t "【zerotier】" "无法获取最新版本" && nvram set zerotier_ver_n="" 
	nvram set zerotier_ver_n=$tag
	if [ -f "$PROG" ] ; then
		chmod +x $PROG
		zt_ver=$($PROG -version | sed -n '1p')
		if [ -z "$zt_ver" ] ; then 
			nvram set zerotier_ver=""
		else
			nvram set zerotier_ver=$zt_ver
		fi
		[ ! -L "$PROGCLI" ] && ln -sf $PROG $PROGCLI
		ztstatus=$($PROGCLI info | awk '{print $5}')
		ztid=$($PROGCLI info | awk '{print $3}')
		nvram set zerotierdev_id=$ztid
		if [ "$ztstatus" = "ONLINE" ]; then
			nvram set zerotier_status="${ztstatus} 在线"
		else
			nvram set zerotier_status="OFFLINE 离线"
		fi
	fi
}

dowload_zero() {
	tag="$1"
	logger -t "【zerotier】" "开始下载 https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one 到 $PROG"
 	bin_path=$(dirname "$PROG")
	[ ! -d "$bin_path" ] && mkdir -p "$bin_path"
	for proxy in $github_proxys ; do
 	length=$(wget --no-check-certificate -T 5 -t 3 "${proxy}https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one" -O /dev/null --spider --server-response 2>&1 | grep "[Cc]ontent-[Ll]ength" | grep -Eo '[0-9]+' | tail -n 1)
        length=`expr $length + 512000`
	length=`expr $length / 1048576`
 	zt_size0="$(check_disk_size $bin_path)"
 	[ ! -z "$length" ] && logger -t "【zerotier】" "程序大小 ${length}M， 程序路径可用空间 ${zt_size0}M "
	curl -Lko "$PROG" "${proxy}https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one" || wget --no-check-certificate -O "$PROG" "${proxy}https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one" || curl -Lkso "$PROG" "https://fastly.jsdelivr.net/gh/lmq8267/ZeroTierOne@master/install/${tag}/zerotier-one" || wget --no-check-certificate -q -O "$PROG" "https://fastly.jsdelivr.net/gh/lmq8267/ZeroTierOne@master/install/${tag}/zerotier-one"
	if [ "$?" = 0 ] ; then
		chmod +x $PROG
		if [[ "$($PROG -h 2>&1 | wc -l)" -gt 2 ]] ; then
			logger -t "【zerotier】" "$PROG 下载成功"
			zt_ver=$($PROG -version | sed -n '1p')
			if [ -z "$zt_ver" ] ; then 
				nvram set zerotier_ver=""
			else
				nvram set zerotier_ver=$zt_ver
			fi
			break
       	else
	   		logger -t "【zerotier】" "下载不完整，请手动下载 ${proxy}https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one 上传到  $PROG"
			rm -rf $PROG
	  	fi
	else
		logger -t "【zerotier】" "下载失败，请手动下载 ${proxy}https://github.com/lmq8267/ZeroTierOne/releases/download/${tag}/zerotier-one 上传到  $PROG"
   	fi
	done
}

update_zero() {
	get_zttag
	[ -z "$tag" ] && logger -t "【zerotier】" "无法获取最新版本" && nvram set zerotier_ver_n="" && exit 1
	if [ ! -z "$tag" ] && [ ! -z "$zt_ver" ] ; then
		if [ "$tag"x != "$zt_ver"x ] ; then
			logger -t "【zerotier】" "当前版本${zt_ver} 最新版本${tag}"
			dowload_zero $tag
		else
			logger -t "【zerotier】" "当前已是最新版本 ${tag} 无需更新！"
		fi
	fi
	exit 0
}

start_zero() {
	zt_enable=$(nvram get zerotier_enable)
	[ "$zt_enable" = "1" ] || exit 1
	logger -t "【zerotier】" "正在启动zerotier"
	sed -Ei '/【zerotier】|^$/d' /tmp/script/_opt_script_check
 	if [ -z "$PROG" ] ; then
  		etc_size=`check_disk_size /etc/storage`
      		if [ "$etc_size" -gt 1 ] ; then
			PROG=/etc/storage/bin/zerotier-one
   		else
     			PROG=/tmp/var/zerotier-one
		fi
 	fi
  	get_zttag
  	zt_dir="$(dirname $PROG)"
   	PROGCLI="${zt_dir}/zerotier-cli"
	PROGIDT="${zt_dir}/zerotier-idtool"
 	if [ -f "$PROG" ] ; then
		[ ! -x "$PROG" ] && chmod +x $PROG
  		[[ "$($PROG -h 2>&1 | wc -l)" -lt 2 ]] && logger -t "【zerotier】" "主程序${PROG}不完整！" && rm -rf $PROG
  	fi
 	if [ ! -f "$PROG" ] ; then
		logger -t "【zerotier】" "主程序${PROG}不存在，开始在线下载..."
  		[ ! -d /etc/storage/bin ] && mkdir -p /etc/storage/bin
    		
  		[ -z "$tag" ] && tag="1.14.2"
  		dowload_zero $tag
  	fi
  	
   	if [ ! -L "$PROGCLI" ] || [ "$(ls -l $PROGCLI | awk '{print $NF}')" != "$PROG" ] ; then
		ln -sf $PROG $PROGCLI
	fi
 	if [ ! -L "$PROGIDT" ] || [ "$(ls -l $PROGIDT | awk '{print $NF}')" != "$PROG" ] ; then
		ln -sf $PROG $PROGIDT
	fi
	kill_z
	start_instance 'zerotier'

}
kill_z() {
	zerotier_process=$(pidof zerotier-one)
	if [ ! -z "$zerotier_process" ]; then
		#logger -t "【zerotier】" "有进程 $zerotier_proces 在运行，结束中..."
		killall zerotier-one >/dev/null 2>&1
		kill -9 "$zerotier_process" >/dev/null 2>&1
	fi
}
stop_zero() {
    	logger -t "【zerotier】" "正在关闭zerotier..."
    	sed -Ei '/【zerotier】|^$/d' /tmp/script/_opt_script_check
	scriptname=$(basename $0)
	del_rules
	zero_route "del"
	kill_z
	#rm -rf $config_path
	logger -t "【zerotier】" "zerotier关闭成功!"
	if [ ! -z "$scriptname" ] ; then
		eval $(ps -w | grep "$scriptname" | grep -v $$ | grep -v grep | awk '{print "kill "$1";";}')
		eval $(ps -w | grep "$scriptname" | grep -v $$ | grep -v grep | awk '{print "kill -9 "$1";";}')
	fi
}

case $1 in
start)
	start_zero &
	;;
stop)
	stop_zero
	;;
update)
	update_zero &
	;;
*)
	echo "check"
	#exit 0
	;;
esac
