# PGSQL Architecture

> Overview of PGSQL module and key concepts 
  

PGSQL for production environments is organized in **clusters**, which **clusters** are **logical entities** consisting of a set of database **instances** associated by **primary-replica**. 
Each **database cluster** is a **self-organizing** business service unit consisting of at least one **database instance**.


----------------

## ER Diagram

Let's get started with ER diagram. There are four types core entities in Pigsty's PGSQL module:

* [**PGSQL Cluster**](#cluster): An autonomous PostgreSQL business unit, used as top level namespace for other entities.  
* [**PGSQL Service**](#service): A named abstraction of cluster ability, route traffics and expose postgres services with node ports.
* [**PGSQL Instance**](#instance): A single postgres server which is a group of running processes & database files on single node. 
* [**PGSQL Node**](#node): An abstraction of hardware resource, which can be bare metal, virtual machine, or even k8s pods.

![PGSQL-ER](https://user-images.githubusercontent.com/8587410/217492920-47613743-88b8-4c21-a8b9-cf7420cdd50f.png)

**Naming Convention**

* Cluster name should be a valid domain name, without any dot: `[a-zA-Z0-9-]+`
* Service name should be prefixed with cluster name, and suffixed with a single word: such as `primary`, `replica`, `offline`, `delayed`, join by `-`
* Instance name is prefixed with cluster name and suffixed with an integer, join by `-`, e.g., `${cluster}-${seq}`.
* Node is identified by its IP address, and its hostname is usually the same as instance name since they are 1:1 deployed.




----------------

## Identity Parameter

Pigsty uses **identity parameters** to identify entities: [`PG_ID`](PARAM#PG_ID).

In addition to the node IP address, three parameters: [`pg_cluster`](PARAM#pg_cluster), [`pg_role`](PARAM#pg_role), and [`pg_seq`](PARAM#pg_seq) are the minimum set of parameters necessary to define a postgres cluster.
Take the [sandbox](PROVISION#sandbox) testing cluster `pg-test` as an example:

```yaml
pg-test:
  hosts:
    10.10.10.11: { pg_seq: 1, pg_role: primary }
    10.10.10.12: { pg_seq: 2, pg_role: replica }
    10.10.10.13: { pg_seq: 3, pg_role: replica }
  vars:
    pg_cluster: pg-test
```

The three members of the cluster are identified as follows.

|  cluster  | seq |   role    |   host / ip   |  instance   |      service      |  nodename   |
|:---------:|:---:|:---------:|:-------------:|:-----------:|:-----------------:|:-----------:|
| `pg-test` | `1` | `primary` | `10.10.10.11` | `pg-test-1` | `pg-test-primary` | `pg-test-1` |
| `pg-test` | `2` | `replica` | `10.10.10.12` | `pg-test-2` | `pg-test-replica` | `pg-test-2` |
| `pg-test` | `3` | `replica` | `10.10.10.13` | `pg-test-3` | `pg-test-replica` | `pg-test-3` |

There are:

* One Cluster: The cluster is named as `pg-test`.
* Two Roles: `primary` and `replica`.
* Three Instances: The cluster consists of three instances: `pg-test-1`, `pg-test-2`, `pg-test-3`.
* Three Nodes: The cluster is deployed on three nodes: `10.10.10.11`, `10.10.10.12`, and `10.10.10.13`.
* Four services:
  *  read-write service:  [`pg-test-primary`](PGSQL-SVC#primary-service)
  * read-only service: [`pg-test-replica`](PGSQL-SVC#replica-service)
  * directly connected management service: [`pg-test-default`](PGSQL-SVC#default-service)
  * offline read service: [`pg-test-offline`](PGSQL-SVC#offline-service)

And in the monitoring system (prometheus/grafana/loki), corresponding metrics will be labeled with these identities：

```yaml
pg_up{cls="pg-meta", ins="pg-meta-1", ip="10.10.10.10", job="pgsql"}
pg_up{cls="pg-test", ins="pg-test-1", ip="10.10.10.11", job="pgsql"}
pg_up{cls="pg-test", ins="pg-test-2", ip="10.10.10.12", job="pgsql"}
pg_up{cls="pg-test", ins="pg-test-3", ip="10.10.10.13", job="pgsql"}
```




----------------

## Component Overview

Here is how PostgreSQL module components and their interactions. From top to bottom:

* Cluster DNS is resolved by DNSMASQ on infra nodes
* Cluster VIP is manged by `vip-manager`, which will bind to cluster primary. 
  * `vip-manager` will acquire cluster leader info written by `patroni` from `etcd` cluster directly
* Cluster service are exposed by Haproxy on nodes, services are distinguished by node ports (543x).
  * Haproxy port 9101 : monitoring metrics & stats & admin page
  * Haproxy port 5433 : default service that route to primary pgbouncer: [primary](PGSQL-SVC#primary-service)
  * Haproxy port 5434 : default service that route to replica pgbouncer: [replica](PGSQL-SVC#replica-service)
  * Haproxy port 5436 : default service that route to primary postgres: [default](PGSQL-SVC#default-service)
  * Haproxy port 5438 : default service that route to offline postgres: [offline](PGSQL-SVC#offline-service)
  * HAProxy will route traffic based on health check information provided by `patroni`. 
* Pgbouncer is a connection pool middleware that buffering connections, exposing extra metrics, and bring extra flexibility @ port 6432
  * Pgbouncer is stateless, and deployed with postgres server in a 1:1 manner through local unix socket.
  * Production traffic (Primary/Replica) will go through pgbouncer by default (can be skipped by [`pg_default_service_dest`](PARAM#pg_default_service_dest)) 
  * Default/Offline service will always bypass pgbouncer and connect to target postgres directly.
* Postgres provides relational database services @ port 5432
  * Install PGSQL module on multiple nodes will automatically form a HA cluster based on streaming replication
  * PostgreSQL is supervised by `patroni` by default.
* Patroni will **supervise** PostgreSQL server @ port 8008 by default
  * Patroni spawn postgres servers as child process
  * Patroni use `etcd` as DCS: config storage, failure detection, and leader election.
  * Patroni will provide postgres information through health check. Which is used by HAProxy
  * Patroni metrics will be scraped by prometheus on infra nodes
* PG Exporter will expose postgres metrics @ port 9630
  * PostgreSQL's metrics will be scraped by prometheus on infra nodes
* Pgbouncer Exporter will expose pgbouncer metrics @ port 9631
  * Pgbouncer metrics will be scraped by prometheus on infra nodes
* pgBackRest will work on local repo by default ([`pgbackrest_method`](PARAM#pgbackrest_method))
  * If `local` (default) is used as backup repo, pgBackRest will create local repo under primary's [`pg_fs_bkup`](PARAM#pg_fs_bkup) 
  * If `minio` is used as backup repo, pgBackRest will create repo on dedicate minio cluster in [`pgbackrest_repo`.`minio`](PARAM#pgbackrest_repo)
* Postgres related logs (postgres,pgbouncer,patroni,pgbackrest) are exposed by promtail @ port 9080
  * Promtail will send log to loki on infra nodes


![pigsty-infra](https://user-images.githubusercontent.com/8587410/206972543-664ae71b-7ed1-4e82-90bd-5aa44c73bca4.gif)



----------------

## High Availability

> Primary Failure RTO ≈ 30s, RPO < 1MB, Replica Failure RTO≈0 (reset current conn)

Pigsty's PostgreSQL cluster has battery-included high-availability powered by [patroni](https://patroni.readthedocs.io/en/latest/), [etcd](https://etcd.io/), and [haproxy](http://www.haproxy.org/) 

![pgsql-ha](https://user-images.githubusercontent.com/8587410/206971583-74293d7b-d29a-4ca2-8728-75d50421c371.gif)

When the primary fails, one of the replica will be promoted to primary automatically, and read-write traffic will be route to the new primary immediately. The impact is: write queries will be blocked for 15 ~ 40s until the new leader is elected.

When a replica fails, read-only traffic will be route to the other replicas, if all replicas fail, read-only traffic will fall back to the primary. The impact would be very small: a few running queries on that replica will abort due to connection reset.

Failure detection is done by `patroni` and `etcd`, the leader will hold a lease, and if it fails, the lease will be released due to timeout, and the other instance will elect a new leader to take over.

The ttl can be tuned with [`pg_rto`](PARAM#pg_rto), which is 30s by default, increasing it will cause longer failover wait time, while decreasing it will increase the false-positive failover rate (e.g. network jitter).

Pigsty will use **availability first** mode by default, which means when primary fails, it will try to failover ASAP, data not replicated to the replica may be lost (usually 100KB), the max potential data loss is controlled by [`pg_rpo`](PARAM#pg_rpo), which is 1MB by default. 
