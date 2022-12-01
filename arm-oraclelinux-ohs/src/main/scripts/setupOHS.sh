#!/bin/bash

#Function to output message to StdErr
function echo_stderr ()
{
    echo "$@" >&2
}

#Function to display usage message
function usage()
{
  echo_stderr "./setupOHS.sh <acceptOTNLicenseAgreement> <otnusername> <otnpassword>"
}


# Following dependencies need to be installed as OHS prerequisites
function installDependencies()
{

echo "Installing all dependencies that are required for OHS"

sudo yum install -y $OHS_DEPNDENCIES

}

#Update the OS patch
function updateOS()
{
	osVersion=`cat /etc/os-release | grep VERSION_ID |cut -f2 -d"="| sed 's/\"//g'`
	majorVersion=`echo $osVersion |cut -f1 -d"."`
	minorVersion=`echo $osVersion |cut -f2 -d"."`
	echo "Kernel version before update:"
	uname -a
	echo yum upgrade -y --disablerepo=ol7_latest  --enablerepo=ol${majorVersion}_u${minorVersion}_base --skip-broken
	yum upgrade -y --disablerepo=ol7_latest  --enablerepo=ol${majorVersion}_u${minorVersion}_base --skip-broken
	yum upgrade -y polkit
	echo "Kernel version after update:"
	uname -a
}

# Download files supplied as part of downloadURL
function downloadUsingWget()
{
   downloadURL=$1
   filename=${downloadURL##*/}
   for in in {1..5}
   do
     echo wget --no-check-certificate $downloadURL
     wget --no-check-certificate $downloadURL
     if [ $? != 0 ];
     then
        echo "$filename Driver Download failed on $downloadURL. Trying again..."
	rm -f $filename
     else 
        echo "$filename Driver Downloaded successfully"
        break
     fi
   done
}

# Update th opatch utility as per opatchURL supplied
function opatchUpdate()
{
	if [ $opatchURL != "none" ];
	then
		sudo mkdir -p ${opatchWork}
		cd ${opatchWork}
		filename=${opatchURL##*/}
		downloadUsingWget "$opatchURL"
		echo "Verifying the ${filename} patch download"
		ls  $filename
		checkSuccess $? "Error : Downloading ${filename} patch failed"
		echo "Opatch version before updating patch"
		runuser -l oracle -c "$oracleHome/OPatch/opatch version"
		unzip $filename
		opatchFileName=`find . -name opatch_generic.jar`
		command="java -jar ${opatchFileName} -silent oracle_home=$oracleHome"
		sudo chown -R $username:$groupname ${opatchWork}
		echo "Executing optach update command:"${command}
		runuser -l oracle -c "cd $oracleHome/wlserver/server/bin ; . ./setWLSEnv.sh ;cd ${opatchWork}; ${command}"
		checkSuccess $? "Error : Updating opatch failed"
		echo "Opatch version after updating patch"
		runuser -l oracle -c "$oracleHome/OPatch/opatch version"
	fi
}

function ohspatchUpdate()
{
	if [ $ohspatchURL != "none" ];
	then
		sudo mkdir -p ${ohsPatchWork}
		cd ${ohsPatchWork}
		downloadUsingWget "$ohspatchURL"
		echo "OHS patch details before applying patch"
		runuser -l oracle -c "$oracleHome/OPatch/opatch lsinventory"
		filename=${ohspatchURL##*/}
		unzip $filename
		sudo chown -R $username:$groupname ${ohsPatchWork}
		sudo chmod -R 755 ${ohsPatchWork}
		#Check whether it is bundle patch
		patchListFile=`find . -name linux64_patchlist.txt`
		if [[ "${patchListFile}" == *"linux64_patchlist.txt"* ]]; 
		then
			echo "Applying OHS Stack Patch Bundle"
			command="${oracleHome}/OPatch/opatch napply -silent -oh ${oracleHome}  -phBaseFile linux64_patchlist.txt"
			echo $command
			runuser -l oracle -c "cd ${ohsPatchWork}/*/binary_patches ; ${command}"
			checkSuccess $? "Error : OHS patch update failed"
		else
			echo "Applying regular OHS patch"
			command="${oracleHome}/OPatch/opatch apply -silent"
			echo $command
			runuser -l oracle -c "cd ${ohsPatchWork}/* ; ${command}"
			checkSuccess $? "Error : OHS patch update failed"
		fi
		echo "OHS patch details after applying patch"
		runuser -l oracle -c "$oracleHome/OPatch/opatch lsinventory"
	fi
}


# Create user "oracle", used for instalation and setup
function addOracleGroupAndUser()
{
    #add oracle group and user
    echo "Adding oracle user and group..."
    USER_GROUP=${groupname}
    sudo groupadd $groupname
    sudo useradd -d ${user_home_dir} -g $groupname $username
}

# Cleaning all installer files 
function cleanup()
{
	echo "Cleaning up temporary files..."
	rm -f $BASE_DIR/$JDK_FILE_NAME
	rm -f $BASE_DIR/$OHS_FILE_NAME
	rm -f $BASE_DIR/setupOHS.sh
	
	rm -f $JDK_PATH/$JDK_FILE_NAME
	rm -f $OHS_PATH/$OHS_FILE_NAME
	rm -f $OHS_PATH/$OHS_INSTALLER_FILE
	rm -rf $OHS_PATH/silent-template
	rm -rf $ohsPatchWork
	
	echo "Cleanup completed."
}

# Verifies whether user inputs are available
function validateInput()
{
    if [ -z "$acceptOTNLicenseAgreement" ];
    then
            echo _stderr "acceptOTNLicenseAgreement is required. Value should be either Y/y or N/n"
            exit 1
    fi
    if [[ ! ${acceptOTNLicenseAgreement} =~ ^[Yy]$ ]];
    then
        echo "acceptOTNLicenseAgreement value not specified as Y/y (yes). Exiting installation Weblogic Server process."
        exit 1
    fi

    if [[ -z "$otnusername" || -z "$otnpassword" ]]
    then
        echo_stderr "otnusername or otnpassword is required. "
        exit 1
    fi	
    
}

# Setup JDK and OHS installation path
function setupInstallPath()
{
    #create custom directory for setting up wls and jdk
    sudo mkdir -p $JDK_PATH
    sudo mkdir -p $OHS_PATH
    sudo chown -R $username:$groupname ${APP_PATH}
    sudo chown -R $username:$groupname ${JDK_PATH}
    sudo chown -R $username:$groupname ${OHS_PATH}
}

# Download JDK for WLS
function downloadJDK()
{
   for in in {1..5}
   do
     curl -s https://raw.githubusercontent.com/typekpb/oradown/master/oradown.sh  | bash -s -- --cookie=accept-weblogicserver-server --username="${otnusername}" --password="${otnpassword}" $JDK_DOWNLOAD_URL
     tar -tzf $JDK_FILE_NAME 
     if [ $? != 0 ];
     then
        echo "Download failed. Trying again..."
        rm -f $JDK_FILE_NAME
     else 
        echo "Downloaded JDK successfully"
        break
     fi
   done
}

# Validate th JDK downloaded checksum
function validateJDKZipCheckSum()
{
  jdkZipFile="$BASE_DIR/$JDK_FILE_NAME"
  
  downloadedJDKZipCheckSum=$(sha256sum $jdkZipFile | cut -d ' ' -f 1)

  if [ "${jdkSha256Checksum}" == "${downloadedJDKZipCheckSum}" ];
  then
    echo "Checksum match successful. Proceeding with Weblogic Install Kit Zip Download from OTN..."
  else
    echo_stderr "Checksum match failed. Please check the supplied OTN credentials and try again."
    exit 1
  fi
}

#Setup JDK required for OHS installation
function setupJDK()
{
    sudo cp $BASE_DIR/$JDK_FILE_NAME $JDK_PATH/$JDK_FILE_NAME

    echo "extracting and setting up jdk..."
    sudo tar -zxf $JDK_PATH/$JDK_FILE_NAME --directory $JDK_PATH
    sudo chown -R $username:$groupname $JDK_PATH

    java -version

    if [ $? == 0 ];
    then
        echo "JAVA HOME set succesfully."
    else
        echo_stderr "Failed to set JAVA_HOME. Please check logs and re-run the setup"
        exit 1
    fi
}


# Download OHS from OTN
function downloadOHS()
{
  echo "Downloading OHS install kit from OTN..."
    for in in {1..5}
  do
     curl -s https://raw.githubusercontent.com/typekpb/oradown/master/oradown.sh  | bash -s -- --cookie=accept-weblogicserver-server --username="${otnusername}" --password="${otnpassword}" $OHS_DOWNLOAD_URL
     unzip -l $OHS_FILE_NAME
     if [ $? != 0 ];
     then
        echo "Download failed. Trying again..."
        rm -f $OHS_FILE_NAME
     else 
        echo "Downloaded WLS successfully"
        break
     fi
  done  
}

#Function to create Weblogic Installation Location Template File for Silent Installation
function create_oraInstlocTemplate()
{
    echo "creating Install Location Template..."

    cat <<EOF >$OHS_PATH/silent-template/oraInst.loc.template
inventory_loc=[INSTALL_PATH]
inst_group=[GROUP]
EOF
}

#Function to create Weblogic Installation Response Template File for Silent Installation
function create_oraResponseTemplate()
{

    echo "creating Response Template..."
    cat <<EOF >$OHS_PATH/silent-template/response.template
[ENGINE]

#DO NOT CHANGE THIS.
Response File Version=1.0.0.0.0

[GENERIC]

#Set this to true if you wish to skip software updates
DECLINE_AUTO_UPDATES=true

#My Oracle Support User Name
MOS_USERNAME=

#My Oracle Support Password
MOS_PASSWORD=<SECURE VALUE>

#If the Software updates are already downloaded and available on your local system, then specify the path to the directory where these patches are available and set SPECIFY_DOWNLOAD_LOCATION to true
AUTO_UPDATES_LOCATION=

#Proxy Server Name to connect to My Oracle Support
SOFTWARE_UPDATES_PROXY_SERVER=

#Proxy Server Port
SOFTWARE_UPDATES_PROXY_PORT=

#Proxy Server Username
SOFTWARE_UPDATES_PROXY_USER=

#Proxy Server Password
SOFTWARE_UPDATES_PROXY_PASSWORD=<SECURE VALUE>

#The oracle home location. This can be an existing Oracle Home or a new Oracle Home
ORACLE_HOME=[INSTALL_PATH]/oracle/middleware/oracle_home

#The federated oracle home locations. This should be an existing Oracle Home. Multiple values can be provided as comma seperated values
FEDERATED_ORACLE_HOMES=

#Set this variable value to the Installation Type selected as either Standalone HTTP Server (Managed independently of WebLogic server) OR Collocated HTTP Server (Managed through WebLogic server)
INSTALL_TYPE=Standalone HTTP Server (Managed independently of WebLogic server)

#The jdk home location.
JDK_HOME=[JAVA_HOME]


EOF

}

# Create OHS silent installation templates
function createOHSTemplates()
{
	sudo cp $BASE_DIR/$OHS_FILE_NAME $OHS_PATH/$OHS_FILE_NAME
	echo "unzipping $OHS_FILE_NAME"
	sudo unzip -o $OHS_PATH/$OHS_FILE_NAME -d $OHS_PATH
	export SILENT_FILES_DIR=$OHS_PATH/silent-template
	sudo mkdir -p $SILENT_FILES_DIR
	sudo rm -rf $OHS_PATH/silent-template/*
	mkdir -p $INSTALL_PATH
	create_oraInstlocTemplate
	create_oraResponseTemplate
	sudo chown -R $username:$groupname $OHS_PATH
	sudo chown -R $username:$groupname $INSTALL_PATH
}

# Install OHS using silent installation
function installOHS()
{
	# Using silent file templates create silent installation required files
    echo "Creating silent files for installation from silent file templates..."
    sed 's@\[INSTALL_PATH\]@'"$INSTALL_PATH"'@' ${SILENT_FILES_DIR}/response.template > ${SILENT_FILES_DIR}/response
    sed -i 's@\[JAVA_HOME\]@'"$JAVA_HOME"'@' ${SILENT_FILES_DIR}/response
    sed 's@\[INSTALL_PATH\]@'"$INSTALL_PATH"'@' ${SILENT_FILES_DIR}/oraInst.loc.template > ${SILENT_FILES_DIR}/oraInst.loc
    sed -i 's@\[GROUP\]@'"$USER_GROUP"'@' ${SILENT_FILES_DIR}/oraInst.loc
    sudo chown -R $username:$groupname $OHS_PATH
	echo "Created files required for silent installation at $SILENT_FILES_DIR"
	echo "---------------- Installing OHS ${OHS_INSTALLER} ----------------"
	runuser -l oracle -c "${OHS_INSTALLER} -silent -invPtrLoc ${SILENT_FILES_DIR}/oraInst.loc -responseFile ${SILENT_FILES_DIR}/response"

	# Check for successful installation and version requested
    if [[ $? == 0 ]];
    then
      echo "OHS Installation is successful"
    else
      echo_stderr "Installation is not successful"
      exit 1
    fi
    echo "#########################################################################################################"
}

# Execution starts here

CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export BASE_DIR="$(readlink -f ${CURR_DIR})"

export acceptOTNLicenseAgreement=$1
export otnusername=$2
export otnpassword=$3
export opatchURL="$4"
export ohspatchURL="$5"
export ohsPatchWork="/u01/app/ohspatch"
export OHS_DEPNDENCIES="zip unzip wget rng-tools binutils compat-libcap1 compat-libstdc++-33 compat-libstdc++-33.i686 gcc gcc-c++ glibc glibc.i686 glibc-devel libaio libaio-devel libgcc libgcc.i686 libstdc++ libstdc++.i686 libstdc++-devel ksh make sysstat numactl numactl-devel"
export APP_PATH="/u01/app"
export JDK_PATH="${APP_PATH}/jdk"
export OHS_PATH="${APP_PATH}/ohs"
export JDK_DOWNLOAD_URL="https://download.oracle.com/otn/java/jdk/8u291-b10/d7fc238d0cbf4b0dac67be84580cfb4b/jdk-8u291-linux-x64.tar.gz"
export JDK_FILE_NAME="jdk-8u291-linux-x64.tar.gz"
export jdkSha256Checksum="c5052d2e1dd9621a44658ef06be145c5cdfcd7ea956c0c9d655ccd64e79c8613"
export JDK_VERSION="jdk1.8.0_291"
export JAVA_HOME=$JDK_PATH/$JDK_VERSION
export PATH=$JAVA_HOME/bin:$PATH
export OHS_FILE_NAME="fmw_12.2.1.4.0_ohs_linux64_Disk1_1of1.zip"
export OHS_VERSION="122140"
export OHS_DOWNLOAD_URL="https://download.oracle.com/otn/nt/middleware/12c/$OHS_VERSION/$OHS_FILE_NAME"
export OHS_INSTALLER_FILE="fmw_12.2.1.4.0_ohs_linux64.bin"
export INSTALL_PATH="$OHS_PATH/install"
export OHS_INSTALLER="$OHS_PATH/$OHS_INSTALLER_FILE"
export groupname="oracle"
export username="oracle"
export user_home_dir="/u01/oracle"

validateInput
addOracleGroupAndUser
installDependencies
updateOS
setupInstallPath
downloadJDK
#validateJDKZipCheckSum
downloadOHS
setupJDK
createOHSTemplates
installOHS
opatchUpdate
ohspatchUpdate
cleanup
