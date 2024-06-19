# etcd-defrag chart

This chart installs a [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
that will periodically defragment the etcd keyspace for a cluster that is managed using
[kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/).

It is installed as part of the [cluster-addons](../cluster-addons) by default.
