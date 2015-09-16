#!/bin/bash 

####################################################
# Clonezilla-BD : Deploy CDH Haddop automativally via CLonezilla 
#
# Description: To deploy CDH Haddop cluster automatically
# Author:
#	Ceasar Sun <ceasar_at_nchc_org_tw>
#
#	Free Software Lab, NCHC, Taiwan
#	License: GPL
####################################################
export PATH=$PATH:/usr/sbin:/bin:/sbin:/sbin
_CLZ2BD_DEFAULT_ROOT="/opt/clz-bd"

# Load Clz2BD setting and functions
_CLZ2BD_WS_DIR=$(cd $(dirname $0) ;pwd)

 [ -d "/opt/clz-bd" ] && _CLZ2BD_ROOT_DIR="$_CLZ2BD_DEFAULT_ROOT" || _CLZ2BD_ROOT_DIR="$_CLZ2BD_WS_DIR"

[ -f "$_CLZ2BD_ROOT_DIR/conf/clz2bd.conf" ] && [ -z "$_LOAD_CLZ2BD_CONF" ] && . $_CLZ2BD_ROOT_DIR/conf/clz2bd.conf
[ -f "$_CLZ2BD_ROOT_DIR/conf/clz2bd-custom.conf" ] && [ -z "$_LOAD_CLZ2BD_CUSTOM_CONF" ] && . $_CLZ2BD_ROOT_DIR/conf/clz2bd-custom.conf


#############
###  Main  ###
#############

# Parse command-line options
while [ $# -gt 0 ]; do
	case "$1" in
		-b|--batch) shift ; _BATCH_MODE="y" ;;
		--debug) shift ; _DEBUG=y ;;
		--deploy)	shift ; _ACTION="deploy" ;;
		-d|--dist)	shift ; _PKG_RELEASE="${_PKG_RELEASE}.${1}" ; shift;;
		-i|--node-install)	shift ; _ACTION="node-install" ;;
		-u|--node-uninstall)	shift ; _ACTION="node-uninstall" ;;
		--ocs-postrun)	shift ; _ACTION="ocs-postrun" ;;
		--ocs-prepare)	shift ; _ACTION="ocs-prepare" ;;
		-v|--verbose) shift ; _VERBOSE="-v" ;;
		--help)	shift ;  _ACTION="print-help" ;;

		--)		shift ; break ;;
		-*)		echo "${0}: ${1}: invalid option" ;   _ACTION="print-help" ; shift ;;
		*)	  _ACTION="print-help" ;shift ;;
	esac
done

[ -n "$(cat /proc/cmdline | grep -iE ' -clzbd|-o1|ocs_postrun*=')" ] && _ACTION="ocs-postrun"

[ -z "$_ACTION" ] && _ACTION="node-install" 

if [ "$_ACTION" = "node-install" ] ; then
	check_if_root;
	check_os_if_support;
	install_necessary_pkg

	echo "Run : Node Prepare "

	[ -f $_CLZ2BD_ROOT_DIR/conf/clz2bd-custom.conf ] && mv $_CLZ2BD_ROOT_DIR/conf/clz2bd-custom.conf $_CLZ2BD_ROOT_DIR/conf/clz2bd-custom.conf.bak
	do_prepare_network
	do_prepare_pkg
	do_prepare_sshkey
	
	[ -d "$_CLZ2BD_DEFAULT_ROOT" ] || rsync -avP --exclude=.git* ${_CLZ2BD_ROOT_DIR}/ ${_CLZ2BD_DEFAULT_ROOT}/

	$SETCOLOR_WARNING; echo "Run : ${_CLZ2BD_DEFAULT_ROOT}/sbin/deploy-bd.sh --deploy " ; $SETCOLOR_NORMAL;
	${_CLZ2BD_DEFAULT_ROOT}/sbin/deploy-bd.sh --deploy

elif [ "$_ACTION" = "ocs-postrun" ] ; then

	echo "Run :OCS Postrun"
	check_drbl_requirement;

	# Start LVM module
	ocs-lvm2-start
	search_target_dev;

	[ -z "$_HD_DEPLOY_DEV" ] && echo "No possible guest OS to deploy" && exit 1;

	mount $_HD_DEPLOY_DEV $_HD_DEPLOY_MOUNT_POINT
	mount -o bind /dev ${_HD_DEPLOY_MOUNT_POINT}/dev
	mount -o bind /dev/pts ${_HD_DEPLOY_MOUNT_POINT}/dev/pts
	mount -o bind /proc ${_HD_DEPLOY_MOUNT_POINT}/proc
	mount -o bind /run ${_HD_DEPLOY_MOUNT_POINT}/run
	mount -o bind /sys ${_HD_DEPLOY_MOUNT_POINT}/sys

	echo "Scratch and mount necessary device within target OS ..."
	# scratch other necessary mount point of guest machine
	_guest_os_mount_ist="$(awk -F " " '$1~/^(UUID|\/dev\/)/ && $2 != "/" && $2 !~ /^(\/media|\/mnt)/ && $3 != "swap"  {print $2} ' ${_HD_DEPLOY_MOUNT_POINT}/etc/fstab)"
	for _mount_p in $_guest_os_mount_ist ;  do
		chroot ${_HD_DEPLOY_MOUNT_POINT} /bin/bash -c "mount $_mount_p"
	done

	$SETCOLOR_WARNING; echo "Sync CLZ-BD fils to target OS: ... "; $SETCOLOR_NORMAL;
	rsync -avP $_CLZ2BD_ROOT_DIR ${_HD_DEPLOY_MOUNT_POINT}/opt

	$SETCOLOR_WARNING; 
	echo "Execute: chroot ${_HD_DEPLOY_MOUNT_POINT} /bin/bash -c \"/opt/$_CLZ2BD_PNAME/sbin/deploy-bd.sh --deploy\"";
	$SETCOLOR_NORMAL;

	chroot ${_HD_DEPLOY_MOUNT_POINT} /bin/bash -c "/opt/$_CLZ2BD_PNAME/sbin/deploy-bd.sh --deploy"
	$SETCOLOR_WARNING; echo "Done and umount target OS ..." ; $SETCOLOR_NORMAL;

	#chroot ${_HD_DEPLOY_MOUNT_POINT} /bin/bash -c "umount -a"
	umount -l ${_HD_DEPLOY_MOUNT_POINT}/sys
	umount -l ${_HD_DEPLOY_MOUNT_POINT}/run
	umount -l ${_HD_DEPLOY_MOUNT_POINT}/proc
	umount -l ${_HD_DEPLOY_MOUNT_POINT}/dev/pts
	umount -l ${_HD_DEPLOY_MOUNT_POINT}/dev
	umount -f -l $_HD_DEPLOY_MOUNT_POINT

	# Stop LVM
	ocs-lvm2-stop

	$SETCOLOR_SUCCESS; echo "Done . Gool luck !"; $SETCOLOR_NORMAL;
 
elif [ "$_ACTION" = "deploy" ] ; then
	echo "Run : Deploy "
	check_os_if_support; 
	install_necessary_pkg
	do_prepare_system_env;
	install_pkg;
	config_system_env;
	config_hadoop_env;
	setup_post_tune_service;

elif [ "$_ACTION" = "ocs-prepare" ] ; then

	check_drbl_requirement;
	check_if_root;
	check_os_if_support;

	echo "Run : OCS Prepare "
	[ -f $_CLZ2BD_ROOT_DIR/conf/clz2bd-custom.conf ] && mv $_CLZ2BD_ROOT_DIR/conf/clz2bd-custom.conf $_CLZ2BD_ROOT_DIR/conf/clz2bd-custom.conf.bak
	do_prepare_network
	do_prepare_pkg
	do_prepare_sshkey

	if [ "${_CLZ2BD_ROOT_DIR%/*}" != "/usr/share/drbl/postrun/ocs" ] ; then
		$SETCOLOR_WARNING;
		read -p "Sync CLZ-BD files to ocs postrun folder (need root privilege) ? [Y/n]" _answer
		$SETCOLOR_NORMAL;
		if [ ! -n "$(echo $_answer | grep -iE "^(n|N)$")" ] ; then
			[  ! -d "/usr/share/drbl/postrun/ocs/$_CLZ2BD_PNAME" ] && mkdir /usr/share/drbl/postrun/ocs/${_CLZ2BD_PNAME}
			rsync -aP --exclude=.git* ${_CLZ2BD_ROOT_DIR}/ /usr/share/drbl/postrun/ocs/${_CLZ2BD_PNAME}/
		fi
	fi

	echo -n "Set a trigger script : '/usr/share/drbl/postrun/ocs/${_CLZ2BD_PNAME}.postrun'"
	cat > /usr/share/drbl/postrun/ocs/${_CLZ2BD_PNAME}.postrun << EOF
#!/bin/bash
# === generated by deploy-bd prepare mmode : do_prepare===
/usr/share/drbl/postrun/ocs/${_CLZ2BD_PNAME}/sbin/deploy-bd.sh --cos-postrun
EOF
	chmod +x /usr/share/drbl/postrun/ocs/${_CLZ2BD_PNAME}.postrun

	$SETCOLOR_SUCCESS;
	echo "Done for OCS preparation.";
	echo "You can modify /usr/share/drbl/postrun/ocs/$_CLZ2BD_PNAME/*.conf with your needs."
	$SETCOLOR_NORMAL;

elif [ "$_ACTION" = "node-uninstall" ] ; then
	check_os_if_support
	echo "Run : Node purge "
	uninstall_clz-bd

elif [ "$_ACTION" = "print-help" ] ; then
	echo "_CLZ2BD_VERSION=$_CLZ2BD_VERSION"
	echo "_PKG_RELEASE=$_PKG_RELEASE"
	echo "
Usage: $0 [actions] [options]
Actions:
  -i, --node-install	Install as template node for deployment. As default action.
  --ocs-prepare		To prepare stuffs  for Clonezilla deployment in Clonezilla-SE server
  --ocs-postrun		For Clonezilla SE postrun script
  --deploy		Real deploy to node. Usually be call by 'node-install' or 'ocs-postrun' actions 
  -u, --node-uninstall	Uninsatll Clz-BD

Options:
  -b, --batch		Batch mode
  -d,--dist [dist]	Assign specified version,ex:  [testing|custom]
  -h, --help		Print help page

Sample:
* As Run '--node-install' , to  install as template node for deployment
   $0
* Use 'testing' distro to run node-install
   $0 -d testing
* To prepare stuffs  for Clonezilla deployment in Clonezilla-SE server and use testing distro  
   $0 --ocs-prepare -d testing
 
Clz_BD is powered by Free Software Lab, NCHC
Report bugs to <ceasar@clonezilla.org>
";

else
	$SETCOLOR_WARNING ;echo "Usage: $0 [--ocs-prepare|--ocs-postrun|--deploy|--node-install|--node-uninstall]"; $SETCOLOR_NORMAL 
fi

exit 0

