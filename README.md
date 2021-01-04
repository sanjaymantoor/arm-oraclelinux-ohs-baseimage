# arm-oraclelinux-ohs-baseimage
# Simple deployment of a Oracle Linux VM with Oracle HTTP Server Installed
This template allows us to deploy a simple Oracle Linux VM with Oracle HTTP Server (12.2.1.4.0) pre-installed. 

<h2> This repository is used for creating OHS Base image at Azure Market place.</h2>
<h3>Using the template</h3>
**Command line**
*#use this command when you need to create a new resource group for your deployment*
</br>
*az group create --name &lt;resource-group-name&gt; --location &lt;resource-group-location&gt;
</br>
*az group deployment create --resource-group &lt;resource-group-name&gt; --template-uri https://raw.githubusercontent.com/sanjaymantoor/arm-oraclelinux-ohs-baseimage/main/arm-oraclelinux-ohs/src/main/arm/mainTemplate.json


