#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
plain='\033[0m'
RM_BASE_PATH="/opt/gost"
os_arch="unknown"
new_version=$2
path=$3
num=$1
if [ -n "$mode" ];then
    new_version=$1
fi


install_base() {
    (command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 && command -v getenforce >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v tar >/dev/null 2>&1) ||
        (install_soft curl wget git unzip python3 jq tar )
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && yum makecache >/dev/null 2>&1 && yum install "$*" selinux-policy -y) ||
        (command -v apt >/dev/null 2>&1 && apt update >/dev/null 2>&1 && apt install "$*" selinux-utils -y) ||
        (command -v apt-get >/dev/null 2>&1 && apt-get update >/dev/null 2>&1 && apt-get install "$*" selinux-utils -y)
}


pre_check() {
    ! command -v systemctl >/dev/null 2>&1 && echo "不支持此系统：未找到 systemctl 命令" && exit 1
    ! command -v yum >/dev/null 2>&1 && ! command -v apt >/dev/null 2>&1 && ! command -v apt-get >/dev/null 2>&1 && echo "不支持此系统：未找到 apt/yum 命令" && exit 1
    # check root
    [[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1
    ## os_arch
    if [[ $(uname -m | grep 'x86_64') != "" ]]; then
        os_arch="amd64"
    elif [[ $(uname -m | grep 'arm') != "" ]]; then
        os_arch="arm64"
    fi
    if [[ ${os_arch} == "unknown" ]];then
        echo -e "${red}暂不支持此架构${plain}"
    fi
    if [ ! -d "$RM_BASE_PATH" ];then
        exixt="${red}未安装${plain}"
        local_version=""
        else
        if [ ! -f "$RM_BASE_PATH/gost" ];then
            exixt="${red}未安装${plain}"
            local_version=""
            else
            local_version="$(/opt/gost/gost -V | awk -F " " '{print $2}')"
            exixt="${green}$(/opt/gost/gost -V | awk -F " " '{print $2}')${plain}"
        fi
    fi
    install_base
}

install_gost(){    
    if [[ $local_version != "" ]]; then
        echo -e "${red}您可能已经安装过gost，当前版本为：${local_version}${plain}"
        echo "退出安装"
        else
        echo -e "> 安装gost"
        if [ ! -n "$new_version" ]; then
            read -e -r -p "请手动指定版本(默认最新版)：" input
            new_version="${input}"
            if [ ! -n "$new_version" ]; then
                RESPONSE=$(curl -sL --retry 2 --connect-timeout 2 https://api.github.com/repos/go-gost/gost/releases)
                LATEST_PRE_RELEASE=$(echo "$RESPONSE" | jq -r "[.[] | select(.prerelease == true)] | .[0]")
                new_version=$(echo "$LATEST_PRE_RELEASE" | jq -r ".tag_name")
                if [ ! -n "$new_version" ]; then
                    echo -e "${red}最新版本获取失败，请检查本机能否链接 api.github.com${plain}"
                    read -e -r -p "请手动指定版本：" input
                    new_version="${input}"
                fi
                if [[ ${new_version} == "null" ]]; then
                    echo -e "${red}最新版本获取失败，请检查本机能否链接 api.github.com${plain}"
                    read -e -r -p "请手动指定版本：" input
                    new_version="${input}"
                fi
            fi
        fi
        echo -e "安装版本为: ${new_version}"
        if [ ! -d "$RM_BASE_PATH" ];then
            mkdir $RM_BASE_PATH
        fi 
        if [ ! -n "$path" ]; then
            path="gost.tar.gz"
            wget -t 1 -T 10 https://github.com/go-gost/gost/releases/download/${new_version}/gost_${new_version#v}_linux_${os_arch}.tar.gz -O gost.tar.gz
            if [[ $? != 0 ]]; then
                echo -e "${red}文件下载失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
                read -e -r -p "请手动文件路径(完整路径)：" input
                path="${input}"
            fi
            tar -zxf "${path}" -C $RM_BASE_PATH
            if [[ $? != 0 ]]; then
                echo -e "${red}安装失败，检查安装包是否存在 ${GITHUB_RAW_URL}${plain}"
                else
                rm -rf "${path}"
                chmod +x $RM_BASE_PATH/gost
                echo -e "${green}gost安装完成${plain}"
            fi
            else
            tar -zxf "${path}" -C $RM_BASE_PATH
            if [[ $? != 0 ]]; then
                echo -e "${red}安装失败，检查安装包是否存在 ${GITHUB_RAW_URL}${plain}"
                else
                rm -rf "${path}"
                chmod +x $RM_BASE_PATH/gost
                echo -e "${green}gost安装完成${plain}"
            fi
        fi                    
    fi
}

update_gost(){
    if [ ! -d "$RM_BASE_PATH" ];then
        echo -e "${red}gost未安装，请先安装gost${plain}"
        else
        if [ ! -f "$RM_BASE_PATH/gost" ];then
            echo -e "${red}gost未安装，请先安装gost${plain}"
            else
            echo "获取版本信息"
            RESPONSE=$(curl -sL --retry 2 --connect-timeout 2 https://api.github.com/repos/go-gost/gost/releases)
            LATEST_PRE_RELEASE=$(echo "$RESPONSE" | jq -r "[.[] | select(.prerelease == true)] | .[0]")
            new_version=$(echo "$LATEST_PRE_RELEASE" | jq -r ".tag_name")
            if [ ! -n "$new_version" ]; then
                echo -e "${red}最新版本获取失败，请检查本机能否链接 api.github.com${plain}"
                read -e -r -p "请手动指定最新版本：" input
                new_version="${input}"
            fi
            local_version=$(/opt/gost/gost -V | awk -F " " '{print $2}')
            echo -e "当前gost版本为：${green}v${local_version}${plain}，最新gost版本为：${green}${new_version}${plain}"
            if [[ $new_version == "${local_version}" ]]; then
                echo -e "${green}当前已是最新版本，无需更新${plain}"
                else
                services=$(systemctl list-units --type=service --all --state=active | grep 'gost' | awk '{print $1}')
                for service in $services; do
                    systemctl stop "$service"
                done
                rm -rf $RM_BASE_PATH/gost
                echo "删除gost" 
                path="gost.tar.gz"
                wget -t 1 -T 10 https://github.com/go-gost/gost/releases/download/${new_version}/gost_3.0.0-nightly.20240920_linux_${os_arch}.tar.gz -O gost.tar.gz
                if [[ $? != 0 ]]; then
                    echo -e "${red}文件下载失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
                    read -e -r -p "请手动文件路径(完整路径)：" input
                    path="${input}"
                fi
                tar -zxf "${path}" -C $RM_BASE_PATH
                if [[ $? != 0 ]]; then
                    echo -e "${red}安装失败，检查安装包是否存在${plain}"
                    else
                    rm "${path}"
                    chmod +x $RM_BASE_PATH/gost
                    systemctl daemon-reload
                    services=$(systemctl list-units --type=service --all --state=failed | grep 'gost' | awk '{print $2}')
                    for service in $services; do
                        systemctl start $service
                    done
                    services=$(systemctl list-units --type=service --all --state=active | grep 'gost' | awk '{print $1}')
                    if [[ $services != "" ]]; then
                        echo -e "${green}gost安装成功，启动成功${plain}"
                        else
                        echo -e "${red}gost安装成功，启动失败${plain}"
                    fi
                fi
            fi
        fi
    fi
}


uninstall_gost(){
    if [ ! -d "$RM_BASE_PATH" ];then
        echo -e "${red}gost未安装，请先安装gost${plain}"
        else
        services=$(systemctl list-units --type=service --all --state=active | grep 'gost' | awk '{print $1}')
        for service in $services; do
            systemctl stop $service
        done
        find /etc/systemd/system/ -name 'gost*.service' -exec rm {} \;
        rm -rf $RM_BASE_PATH
        systemctl daemon-reload
        systemctl reset-failed
        echo -e "${red}gost卸载完毕${plain}"
    fi
}

show_menu() {    
    echo -e "
  ${green}gost一键安装脚本${plain} 

  ${green}1.${plain}  安装 gost

  ${green}2.${plain}  更新 gost

  ${green}3.${plain}  卸载 gost

  ${green}0.${plain} 退出脚本

  gost版本：${exixt}
    "
    echo && read -ep "请输入选择 [0-13]: " num
    case "${num}" in
        1)
            install_gost
            ;;
        2)
            update_gost
            ;;
        3)
            uninstall_gost
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${red}请输入正确的数字 [0-2]${plain}"
            ;;
        esac
}

pre_check


if [ ! -n "$num" ]; then
    show_menu
    else
    if [[ $num == 1 ]]; then
        install_gost
    fi
    if [[ $num == 2 ]]; then
        update_gost
    fi
    if [[ $num == 3 ]]; then
        uninstall_gost
    fi
fi