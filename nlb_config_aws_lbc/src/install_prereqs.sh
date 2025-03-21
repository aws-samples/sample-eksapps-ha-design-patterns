#!/bin/bash

# Variables
stack="eks-nlb"
acctid=$(aws sts get-caller-identity --query 'Account' --output text)
rolearn="arn:aws:iam::${acctid}:role/AmazonEKSLoadBalancerControllerRole"
vpcid=$(aws cloudformation describe-stacks --stack-name ${stack} --query "Stacks[0].Outputs[?OutputKey=='VPCId'].OutputValue" --output text)

# Install ApacheBench
sudo yum -y install httpd-tools

# Install AWS CLI
curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
unzip awscliv2.zip > /dev/null
sudo ./aws/install
rm -rf ./aws awscliv2.zip
aws --version

# Install eksctl
curl -sLO https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz
sudo tar -xzf eksctl_Linux_amd64.tar.gz -C /usr/local/bin/
eksctl version
rm -rf eksctl_Linux_amd64.tar.gz

# Install kubectl
curl -sLO https://dl.k8s.io/release/v1.27.0/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv -f kubectl /usr/local/bin/
kubectl version --client

# Install helm
curl -sLO https://get.helm.sh/helm-v3.16.2-linux-amd64.tar.gz
tar -xzf helm-v3.16.2-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/
rm -rf helm-v3.16.2-linux-amd64.tar.gz ./linux-amd64

helm repo add eks https://aws.github.io/eks-charts

# Configure kubeconfig
for clu in "pri-eks-clu1" "sec-eks-clu1"
do
  aws eks update-kubeconfig --name ${clu} --alias ${clu}
  eksctl utils associate-iam-oidc-provider --cluster ${clu} --approve
  eksctl create iamserviceaccount --cluster=${clu} --namespace=kube-system --name=aws-load-balancer-controller --attach-role-arn=${rolearn} --approve
  helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=${clu} --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --set vpcId=${vpcid}
done

echo Sleeping for 60 seconds for the LB Controller deployment to be ready ..
sleep 60
# Create deployment, Service for nginx
for clu in "pri-eks-clu1"
do
  kubectl config use-context ${clu}
  if [[ $? -ne 0 ]]; then
	echo "Failed to set context for cluster ${clu}"
	exit 1
  fi
  kubectl create -f nginxapp.yaml
  kubectl create -f nginx_${clu}.yaml
  # kubectl get all
done

echo Sleep 30 seconds for the nginx deployment to be ready..
sleep 30
echo Primary EKS Cluster
kubectl config use-context pri-eks-clu1
kubectl get all -n default

echo Secondary EKS Cluster
kubectl config use-context sec-eks-clu1
kubectl get all -n default

