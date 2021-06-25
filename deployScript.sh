KEY_NAME="cloud-course-`date +'%N'`"
KEY_PEM="$KEY_NAME.pem"

echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM

# Secure the key pair
chmod 400 $KEY_PEM

SEC_GRP="my-sg-`date +'%N'`"
LOAD_BALANCER="my-elb-`date +'%N'`"

echo "setup firewall $SEC_GRP"
SEC_GRP_OUTPUT=$(aws ec2 create-security-group   \
    --group-name $SEC_GRP       \
    --description "Access my instances")

SEC_GRP_ID=$(echo $SEC_GRP_OUTPUT | jq -r '.GroupId')
echo "$SEC_GRP_ID"

echo "setup rule"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 22 --protocol tcp \
    --cidr "0.0.0.0"/0
echo "setup rule"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 3000 --protocol tcp \
    --cidr "0.0.0.0"/0
echo "setup rule"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 6379 --protocol tcp \
    --cidr "0.0.0.0"/0


# Create Main Instance.
UBUNTU_20_04_AMI="ami-042e8287309f5df03"

echo "Creating Ubuntu 20.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t3.micro            \
    --key-name $KEY_NAME                \
    --security-groups $SEC_GRP)

INSTANCE_ID_MAIN=$(echo $RUN_INSTANCES | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID_MAIN

PUBLIC_IP_1=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID_MAIN | 
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)
SUBNET_ID=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID_MAIN | 
    jq -r '.Reservations[0].Instances[0].SubnetId'
)

echo "Created new Instance - $INSTANCE_ID_MAIN @ $PUBLIC_IP_1 $SUBNET_ID"

echo "setup production environment"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_1 <<EOF
    echo "New instance $INSTANCE_ID @ $PUBLIC_IP_1"
    sudo apt update
    sudo apt install curl -y
    sudo apt install screen -y
    curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
    sudo apt install nodejs -y
    sudo apt install redis-server -y
	sudo apt install git -y
    sudo systemctl stop redis-server
    sudo sed -i 's/bind 127.0.0.1 ::1/bind 0.0.0.0/g' /etc/redis/redis.conf
    sudo sed -i 's/protected-mode yes/protected-mode no/g' /etc/redis/redis.conf
    sudo systemctl start redis-server
    git clone https://github.com/ofirnash/CloudComputing-Ex2.git
    cd CloudComputing-Ex2
    npm install
    nohup node server.js $PUBLIC_IP_1 >> app.log 2>&1 &
    exit
EOF


# Create Secondary Instance.
UBUNTU_20_04_AMI="ami-042e8287309f5df03"

echo "Creating Ubuntu 20.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t3.micro            \
    --key-name $KEY_NAME                \
    --security-groups $SEC_GRP)

INSTANCE_ID_SECONDARY=$(echo $RUN_INSTANCES | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID_SECONDARY

PUBLIC_IP_2=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID_SECONDARY | 
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "Created new Instance - $INSTANCE_ID_SECONDARY @ $PUBLIC_IP_2"

echo "setup production environment"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP_2 <<EOF
    echo "New instance $INSTANCE_ID @ $PUBLIC_IP_1"
    sudo apt update
    sudo apt install curl -y
    curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
    sudo apt install nodejs -y
    sudo apt install redis-server -y
	sudo apt install git -y
    redis-server &
    git clone https://github.com/ofirnash/CloudComputing-Ex2.git
    cd CloudComputing-Ex2
    npm install
    nohup node server.js $PUBLIC_IP_1 >> app.log 2>&1 &
    exit
EOF


# Create Load Balancer
aws elb create-load-balancer --load-balancer-name $LOAD_BALANCER \
--listeners Protocol=HTTP,LoadBalancerPort=3000,InstanceProtocol=HTTP,InstancePort=3000 \
--subnets $SUBNET_ID --security-groups $SEC_GRP_ID 

aws elb register-instances-with-load-balancer --load-balancer-name $LOAD_BALANCER \
--instances $INSTANCE_ID_MAIN $INSTANCE_ID_SECONDARY


# Sleep used for testing.
# Used for testing only two Instances - Main and secondary in order to not overload..
sleep 30