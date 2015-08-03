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
		-d|--debug) shift ; _DEBUG=y ;;
		--deploy)	shift ; _ACTION="deploy" ;;
		-i|--node-install)	shift ; _ACTION="node-install" ;;
		-u|--node-uninstall)	shift ; _ACTION="node-uninstall" ;;
		--ocs-prepare)	shift ; _ACTION="ocs-prepare" ;;
		--ocs-deploy)	shift ; _ACTION="ocs-deploy" ;;
		--post-tune)	shift ; _ACTION="post-tune" ;;
		-v|--verbose) shift ; _VERBOSE="-v" ;;
		-V|--version) shift ; do_print_version=y  ;;

		--help)	shift ; do_print_help=y ;;

		--)		shift ; break ;;
		-*)		echo "${0}: ${1}: invalid option" ; do_print_help=y; 	shift ;;
		*)	do_print_help=y ;shift ;;
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
	echo "Execute: chroot ${_HD_DEPLOY_MOUNT_POINT} /bin/bash -c \"/opt/$_CLZ2BD_PNAME/sbin/deploy-bd.sh --ocs-deploy\"";
	$SETCOLOR_NORMAL;

	chroot ${_HD_DEPLOY_MOUNT_POINT} /bin/bash -c "/opt/$_CLZ2BD_PNAME/sbin/deploy-bd.sh --ocs-deploy"
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
	echo "Run : OCS Deploy "
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
else
	$SETCOLOR_WARNING ;echo "Usage: $0 [--ocs-prepare|--ocs-postrun|--deploy|--node-install|--node-uninstall]"; $SETCOLOR_NORMAL 
fi

exit 0

