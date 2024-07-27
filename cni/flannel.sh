#!/bin/bash
kubectl create ns kube-flannel
kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged
helm repo add flannel https://flannel-io.github.io/flannel/
# podCidr must match k8s's --pod-network-cidr
helm install flannel --set podCidr="192.168.0.0/16" --namespace kube-flannel flannel/flannel