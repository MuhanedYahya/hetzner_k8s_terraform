#!/bin/bash

helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.15.5 --namespace kube-system