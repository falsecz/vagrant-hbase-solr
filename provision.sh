#!/bin/bash -e

HBASE_VERSION=0.98.7
HADOOP_VERSION=2.5.1
SOLR_VERSION=4.10.2

## Install java
if ! which java > /dev/null; then
	apt-get update
	apt-get install -y -qq mc screen htop dstat git
	apt-get install python-software-properties -y
	add-apt-repository -y ppa:webupd8team/java
	apt-get update
	echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
	echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections
	apt-get install oracle-java7-installer -y

fi

apt-get install -y -qq psmisc

# apt-get install -y -qq maven2

## Setup java home
echo echo Setting javahome to  /usr/lib/jvm/java-7-oracle/ >  /etc/profile.d/javahome.sh
echo export JAVA_HOME=/usr/lib/jvm/java-7-oracle/ >>  /etc/profile.d/javahome.sh
chmod +x /etc/profile.d/javahome.sh
export JAVA_HOME=/usr/lib/jvm/java-7-oracle/


if ! which mvn > /dev/null; then
	add-apt-repository -y ppa:natecarlson/maven3
	apt-get update
	apt-get install maven maven3 -y -qq
fi



## Download hbase
if [ ! -d "hbase-$HBASE_VERSION-hadoop2" ]; then
	echo Downloading hbase
	rm -rf hbase-$HBASE_VERSION-hadoop2-bin.tar.gz
	wget -q http://apache.miloslavbrada.cz/hbase/hbase-$HBASE_VERSION/hbase-$HBASE_VERSION-hadoop2-bin.tar.gz
	tar -xzf hbase-$HBASE_VERSION-hadoop2-bin.tar.gz
fi


## Download hadoop
if [ ! -d "hadoop-$HADOOP_VERSION" ]; then
	echo Downloading hadoop
	rm -rf hadoop-$HADOOP_VERSION.tar.gz
	wget -q http://mirror.hosting90.cz/apache/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz
	tar -xzf hadoop-$HADOOP_VERSION.tar.gz
fi


## Solr hadoop
if [ ! -d "solr-$SOLR_VERSION" ]; then
	echo Downloading solr
	rm -rf solr-$SOLR_VERSION.tar.gz
	wget -q http://mirror.hosting90.cz/apache/lucene/solr/4.10.2/solr-$SOLR_VERSION.tgz
	tar -xzf solr-$SOLR_VERSION.tgz
fi

if [ ! -f "hbase-indexer/hbase-indexer-dist/target/hbase-indexer-dist-1.6-SNAPSHOT.jar" ]; then
	rm -rf hbase-indexer
	git clone https://github.com/falsecz/hbase-indexer.git
	cd hbase-indexer
	mvn -B clean package -Pdist -DskipTests -D hbase.api=0.98
	cd ..
fi




## Configuration
cp /vagrant_data/hbase-site.xml hbase-$HBASE_VERSION-hadoop2/conf/
cp /vagrant_data/hadoop-site.xml hadoop-$HADOOP_VERSION/etc/hadoop/
cp /vagrant_data/.screenrc /home/vagrant/
cp /vagrant_data/.screenrc /root/
cp /vagrant_data/hbase-indexer-site.xml hbase-indexer/conf/
cp /vagrant_data/indexdemo-indexer.xml ./


cp hbase-indexer/hbase-indexer-dist/target/hbase-indexer-1.6-SNAPSHOT/hbase-indexer-1.6-SNAPSHOT/lib/hbase-sep-* hbase-$HBASE_VERSION-hadoop2/lib/


if [ ! -d "/tmp/hadoop-root/dfs/name" ]; then
	echo Formating namenode
	hadoop-2.5.1/bin/hdfs namenode -format
fi

if ! screen -v | grep 4.02.01 > /dev/null; then
	rm -rf screen_4.2.1-2~ubuntu14.04.1_amd64.deb
	wget https://launchpad.net/ubuntu/+source/screen/4.2.1-2~ubuntu14.04.1/+build/6255177/+files/screen_4.2.1-2~ubuntu14.04.1_amd64.deb
	dpkg -i screen_4.2.1-2~ubuntu14.04.1_amd64.deb
fi


SCREENS=""
runinscreen() {
	local NAME="solr-vagrant"

	if  ! screen -ls | grep $NAME > /dev/null; then
		screen -dmS $NAME
	fi


	if screen -S $NAME -Q windows | grep "$1" > /dev/null; then
		echo -n
	else
		echo "----> Starting $1"
		screen -S $NAME -x -X screen -t $1 bash
		sleep 1
		screen -S $NAME -X  select $1
		sleep 1
		screen -S $NAME -X stuff "$2"`echo -ne '\015'`
	fi

	# screen -S mrdka -x -X screen -t baba bash


	# if screen -ls | grep $1 > /dev/null; then
	# 	echo "Screen with $1 already running"
	# else
	# 	echo "----> Starting screen with $1"
	#
	# 	screen -S test -X  select baba
	# 	screen -S test -X  stuff 'ls'`echo -ne '\015'`
	#
	# 	# screen -S daemons -x -X screen
	# 	# screen -dmS $1 $2
	# fi
}

runinscreen zookeeper "hbase-$HBASE_VERSION-hadoop2/bin/hbase zookeeper start"

runinscreen namenode "hadoop-$HADOOP_VERSION/bin/hdfs namenode"
runinscreen datanode "hadoop-$HADOOP_VERSION/bin/hdfs datanode"
runinscreen resourcemanager "hadoop-$HADOOP_VERSION/bin/yarn resourcemanager"
runinscreen nodemanager "hadoop-$HADOOP_VERSION/bin/yarn nodemanager"


runinscreen hbasemaster "hbase-$HBASE_VERSION-hadoop2/bin/hbase master start"
runinscreen regionserver "hbase-$HBASE_VERSION-hadoop2/bin/hbase regionserver start"



runinscreen solr "solr-$SOLR_VERSION/bin/solr -f -c -z 10.11.1.13:2181/solr -f -c -z 127.0.0.1:2181/solr"


runinscreen hbaseshell "hbase-$HBASE_VERSION-hadoop2/bin/hbase shell"
runinscreen zkcli "hbase-$HBASE_VERSION-hadoop2/bin/hbase zkcli"
runinscreen hbaseindexer "hbase-indexer/bin/hbase-indexer"


# -a \"-Dbootstrap_confdir=./solr/collection1/conf -Dcollection.configName=myconf\"
# bin/solr -f -c -z 10.11.1.13:2181/solr -a "-Dbootstrap_confdir=./solr/collection1/conf -Dcollection.configName=myconf"
#
# rm -rf ~/.m2/repository/org/sonatype
# cat > ~/.m2/settings.xml <<DONE
# <settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
#       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
#       xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
#                           http://maven.apache.org/xsd/settings-1.0.0.xsd">
#   <mirrors>
#     <mirror>
#       <id>HTTPSsourceforge</id>
#       <name>HTTPSsourceforge</name>
#       <url>https://oss.sonatype.org/content/groups/public/</url>
#       <mirrorOf>sourceforge</mirrorOf>
#     </mirror>
#   </mirrors>
# </settings>
# DONE
#
#  mvn dependency:copy-dependencies



echo Done


## Dump info
IP=`ifconfig eth0 | grep "inet addr" | cut -f 2 -d: | cut -f 1 -d" "`
echo " "
echo hbasemaster:       http://$IP:60010/
echo namenode:          http://$IP:50070/
echo datanode:          http://$IP:50075/
echo resource manager:  http://$IP:8088/
echo nodemanager:       http://$IP:8042/
echo solr:              http://$IP:8983/solr/

echo " "
echo "to attach to screen run:"
echo "  sudo screen -x solr-vagrant"
echo " "