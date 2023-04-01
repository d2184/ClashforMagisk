#!/system/bin/sh

scripts=$(realpath $0)
scripts_dir=$(dirname ${scripts})
source /data/clash/clash.config
user_agent="ClashForMagisk"

find_packages_uid() {
  echo -n "" > ${appuid_file} 
  if [ "${Clash_enhanced_mode}" == "redir-host" ] ; then
    for package in $(cat ${filter_packages_file} | sort -u) ; do
      ${busybox_path} awk '$1~/'^"${package}"$'/{print $2}' ${system_packages_file} >> ${appuid_file}
    done
  else
    log "[info] enhanced-mode: ${Clash_enhanced_mode} "
    log "[info] if you want to use whitelist and blacklist, use enhanced-mode: redir-host"
  fi
}

restart_clash() {
  ${scripts_dir}/clash.service -k && ${scripts_dir}/clash.iptables -k
  echo -n "disable" > ${Clash_run_path}/root
  sleep 0.5
  ${scripts_dir}/clash.service -s && ${scripts_dir}/clash.iptables -s
  if [ "$?" == "0" ] ; then
    log "[info] $(date), clash restarted"
  else
    log "[error] $(date), clash failed to restart."
  fi
}

update_file() {
    file="$1"
    file_bak="${file}.bak"
    update_url="$2"
    if [ -f ${file} ]; then
      mv -f ${file} ${file_bak}
    fi
    
    if [ "${signal}" == "o" ]; then
      request="/data/adb/magisk/busybox wget"
      request+=" --no-check-certificate"
      request+=" --user-agent ${user_agent}"
      request+=" -O ${file}"
      request+=" ${update_url}"
      echo $request
      $request 2>&1
    else
      echo "/data/adb/magisk/busybox wget --no-check-certificate ${update_url} -o ${file}"
      /data/adb/magisk/busybox wget --no-check-certificate ${update_url} -O ${file} 2>&1
    fi
    
    sleep 0.5
    if [ -f "${file}" ]; then
      echo -e "\nupdate success"
    else
      if [ -f "${file_bak}" ]; then
        echo -e "\nfailed to update and restore old files"
        mv ${file_bak} ${file}
      fi
    fi
}

update_geo() {
  update_file ${Clash_GeoIP_file} ${GeoIP_dat_url}
  echo -e "\n"
  update_file ${Clash_GeoSite_file} ${GeoSite_url}
  echo -e "\n"

  rm -rf ${Clash_data_dir}/*mmdb.bak 
  rm -rf ${Clash_data_dir}/*dat.bak
  
  if [ -f "${Clash_pid_file}" ]; then
    restart_clash
  fi
}

config_online() {
  clash_pid=$(cat ${Clash_pid_file})
  match_count=0
  log "[warning] download config online" > ${CFM_logs_file}
  update_file ${Clash_config_file} ${Subcript_url}
  sleep 0.5
  if [ -f "${Clash_config_file}" ] ; then
    match_count=$((${match_count} + 1))
  fi

  if [ ${match_count} -ge 1 ] ; then
    log "[info] download succes."
    exit 0
  else
    log "[error] download failed, make sure the url is not empty"
    exit 1
  fi
  
  if [ -f "${Clash_pid_file}" ]; then
    restart_clash
  fi
}

port_detection() {
  clash_pid=$(cat ${Clash_pid_file})
  match_count=0
  
  if (ss -h > /dev/null 2>&1)
  then
    clash_port=$(ss -antup | grep "clash" | ${busybox_path} awk '$7~/'pid="${clash_pid}"*'/{print $5}' | ${busybox_path} awk -F ':' '{print $2}' | sort -u)
  else
    logs "[info] skip port detected"
    exit 0
  fi

  logs "[info] port detected: "
  for sub_port in ${clash_port[*]} ; do
    sleep 0.5
    echo -n "${sub_port} " >> ${CFM_logs_file}
  done
    echo "" >> ${CFM_logs_file}
}

update_kernel() {
  if [ "${use_premium}" == "false" ] ; then
    if [ "${meta_alpha}" == "false" ] ; then
      tag_meta=$(/data/adb/magisk/busybox wget --no-check-certificate -qO- ${url_meta} | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" | head -1)
      filename="${file_kernel}-${platform}-${arch}-cgo-${tag_meta}"
      update_file "${Clash_data_dir}/${file_kernel}.gz" "${url_meta}/download/${tag_meta}/${filename}.gz"
        if [ "$?" == "0" ]; then
          flag=false
        fi
    else
      tag_meta=$(/data/adb/magisk/busybox wget --no-check-certificate -qO- ${url_meta}/expanded_assets/${tag} | grep -oE "${tag_name}" | head -1)
      filename="${file_kernel}-${platform}-${arch}-cgo-${tag_meta}"
      update_file "${Clash_data_dir}/${file_kernel}.gz" "${url_meta}/download/${tag}/${filename}.gz"
        if [ "$?" == "0" ]; then
          flag=false
        fi
    fi
  else
    if [ "${dev}" != "false" ]; then
      update_file "${Clash_data_dir}/${file_kernel}.gz" "https://release.dreamacro.workers.dev/latest/clash-linux-${arch}-latest.gz"
        if [ "$?" == "0" ]; then
          flag=false
        fi
    else
      filename=$(/data/adb/magisk/busybox wget --no-check-certificate -qO- "${url_premium}/expanded_assets/premium" | grep -oE "clash-${platform}-${arch}-[0-9]+.[0-9]+.[0-9]+" | head -1)
      update_file "${Clash_data_dir}/${file_kernel}.gz" "${url_premium}/download/premium/${filename}.gz"
        if [ "$?" == "0" ]; then
          flag=false
        fi
    fi
  fi

  if [ ${flag} == false ] ; then
    if (gunzip --help > /dev/null 2>&1); then
       if [ -f "${Clash_data_dir}/${file_kernel}.gz" ] ; then
        if (gunzip "${Clash_data_dir}/${file_kernel}.gz"); then
          echo ""
        else
          log "[error] gunzip ${file_kernel}.gz failed"  > ${CFM_logs_file}
          log "[warning] please double check the url"
          if [ -f "${Clash_data_dir}/${file_kernel}.gz.bak" ] ; then
            rm -rf "${Clash_data_dir}/${file_kernel}.gz.bak"
          else
            rm -rf "${Clash_data_dir}/${file_kernel}.gz"
          fi
          if [ -f ${Clash_run_path}/clash.pid ] ; then
            log "[info] clash service is running (PID: $(cat ${Clash_pid_file}))"
          fi
          exit 1
        fi
       else
        log "[warning] gunzip ${file_kernel}.gz failed" 
        log "[warning] please make sure there is an internet connection" 
        exit 1
      fi
    else
      log "[error] gunzip not found" 
      exit 1
    fi
  fi

  mv -f "${Clash_data_dir}/${file_kernel}" ${Clash_data_dir}/kernel/lib

  if [ "$?" == "0" ] ; then
    flag=true
  fi

  if [ -f "${Clash_pid_file}" ] && [ ${flag} == true ] ; then
    restart_clash
  else
     log "[warning] clash does not restart"
  fi
}

cgroup_limit() {
  if [ "${Cgroup_memory_limit}" == "" ] ; then
    return
  fi
  if [ "${Cgroup_memory_path}" == "" ] ; then
    Cgroup_memory_path=$(mount | grep cgroup | ${busybox_path} awk '/memory/{print $3}' | head -1)
  fi

  mkdir -p "${Cgroup_memory_path}/clash"
  echo $(cat ${Clash_pid_file}) > "${Cgroup_memory_path}/clash/cgroup.procs" \
  && log "[info] ${Cgroup_memory_path}/clash/cgroup.procs"  

  echo "${Cgroup_memory_limit}" > "${Cgroup_memory_path}/clash/memory.limit_in_bytes" \
  && log "[info] ${Cgroup_memory_path}/clash/memory.limit_in_bytes"
}

update_dashboard() {
  if [ "${use_premium}" == "false" ]; then
    url_dashboard="https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip"
    file_dashboard="${Clash_data_dir}/dashboard.zip"

    /data/adb/magisk/busybox wget --no-check-certificate ${url_dashboard} -O ${file_dashboard} 2>&1
    if [ -e ${file_dashboard} ]; then
      rm -rf ${Clash_data_dir}/dashboard/dist
    else
      echo "update dashboard failed !!!"
      exit 1
    fi
    unzip -o  "${file_dashboard}" "Yacd-meta-gh-pages/*" -d ${Clash_data_dir}/dashboard >&2
    mv -f ${Clash_data_dir}/dashboard/Yacd-meta-gh-pages ${Clash_data_dir}/dashboard/dist
    rm -rf ${file_dashboard}
  else
    url_dashboard="https://github.com/haishanh/yacd/archive/refs/heads/gh-pages.zip"
    file_dashboard="${Clash_data_dir}/dashboard.zip"
    rm -rf ${Clash_data_dir}/dashboard/dist

    /data/adb/magisk/busybox wget --no-check-certificate ${url_dashboard} -O ${file_dashboard} 2>&1
    if [ -e ${file_dashboard} ]; then
      rm -rf ${Clash_data_dir}/dashboard/dist
    else
      echo "update dashboard failed !!!"
      exit 1
    fi
    unzip -o  "${file_dashboard}" "yacd-gh-pages/*" -d ${Clash_data_dir}/dashboard >&2
    mv -f ${Clash_data_dir}/dashboard/yacd-gh-pages ${Clash_data_dir}/dashboard/dist
    rm -rf ${file_dashboard}
  fi
}

while getopts ":dfklopsv" signal ; do
  case ${signal} in
    d)
      update_dashboard 
      ;;
    f)
      find_packages_uid
      ;;
    k)
      update_kernel
      ;;
    l)
      cgroup_limit
      ;;
    o)
      config_online
      ;;
    p)
      port_detection
      ;;
    s)
      update_geo
      ;;
    ?)
      echo ""
      ;;
  esac
done
