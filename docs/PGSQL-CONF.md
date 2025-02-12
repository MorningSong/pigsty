# PGSQL Configuration

> Define roles & clusters for PostgreSQL

You can define different types of instances & clusters.

- [Identity](#identity): Parameters used for describing a PostgreSQL cluster
- [Primary](#primary): Define a single instance cluster.
- [Replica](#replica): Define a basic HA cluster with one primary & one replica.
- [Offline](#offline): Define a dedicated instance for OLAP/ETL/Interactive queries
- [Sync Standby](#sync-standby): Enable synchronous commit to ensure no data loss.
- [Quorum Commit](#quorum-commit):   Use quorum sync commit for an even higher consistency level.
- [Standby Cluster](#standby-cluster): Clone an existing cluster and follow it
- [Delayed Cluster](#delayed-cluster): Clone an existing cluster for emergency data recovery
- [Citus Cluster](#citus-cluster): Define a Citus distributed database cluster



----------------

## Primary

Let's start with the simplest case, singleton meta:

```yaml
pg-test:
  hosts:
    10.10.10.11: { pg_seq: 1, pg_role: primary }
  vars:
    pg_cluster: pg-test
```

Use the following command to create a primary database instance on the `10.10.10.11` node.

```bash
bin/pgsql-add pg-test
```



----------------

## Replica

To add a physical replica, you can assign a new instance to `pg-test` with [`pg_role`](PARAM#pg_role) set to `replica`

```yaml
pg-test:
  hosts:
    10.10.10.11: { pg_seq: 1, pg_role: primary }
    10.10.10.12: { pg_seq: 2, pg_role: replica }  # <--- newly added
  vars:
    pg_cluster: pg-test
```

You can [create](PGSQL-ADMIN#create-cluster) an entire cluster or [append](PGSQL-ADMIN#append-replica) a replica to the existing cluster:

```bash
bin/pgsql-add pg-test               # init entire cluster in one-pass
bin/pgsql-add pg-test 10.10.10.12   # add replica to existing cluster
```


----------------

## Offline

The offline instance is a dedicated replica to serve slow queries, ETL, OLAP traffic and interactive queries, etc...

To add an offline instance, assign a new instance with [`pg_role`](PARAM#pg_role) set to `offline`.

```yaml
pg-test:
  hosts:
    10.10.10.11: { pg_seq: 1, pg_role: primary }
    10.10.10.12: { pg_seq: 2, pg_role: replica }
    10.10.10.13: { pg_seq: 2, pg_role: offline } # <--- newly added
  vars:
    pg_cluster: pg-test
```

Offline instance works like common replica instances, but it is used as a backup server in `pg-test-replica` service.
That is to say, offline and primary instance serves only when all `replica` instances are down.

You can have ad hoc access control offline with [`pg_default_hba_rules`](PARAM#pg_default_hba_rules) and [`pg_hba_rules`](PARAM#pg_hba_rules). 
It will apply to the offline instance and any instances with [`pg_offline_query`](PARAM#pg_offline_query) flag.



----------------

## Sync Standby

PostgreSQL uses asynchronous commit in stream replication by default. Which may have a small replication lag. (10KB / 10ms).
A small window of data loss may occur when the primary fails (can be controlled with [`pg_rpo`](PARAM#pg_rpo).), but it is acceptable for most scenarios. 

But in some critical scenarios (e.g. financial transactions), data loss is totally unacceptable or read-your-write consistency is required.
In this case, you can enable synchronous commit to ensure that.

To enable sync standby mode, you can simply use `crit.yml` template in [`pg_conf`](PARAM#pg_conf)

```yaml
pg-test:
  hosts:
    10.10.10.11: { pg_seq: 1, pg_role: primary }
    10.10.10.12: { pg_seq: 2, pg_role: replica }
    10.10.10.13: { pg_seq: 3, pg_role: replica }
  vars:
    pg_cluster: pg-test
    pg_conf: crit.yml   # <--- use crit template
```

To enable sync standby on existing clusters, [config](PGSQL-ADMIN#config-cluster) the cluster and enable `synchronous_mode`:

```bash
$ pg edit-config pg-test    # run on admin node with admin user
+++
-synchronous_mode: false    # <--- old value
+synchronous_mode: true     # <--- new value
 synchronous_mode_strict: false

Apply these changes? [y/N]: y
```



----------------

## Quorum Commit

When [sync standby](#sync-standby) is enabled, PostgreSQL will pick one replica as the standby instance, and all other replicas as candidates.
Primary will wait until the standby instance flushes to disk before a commit is confirmed, and the standby instance will always have the latest data without any lags.

However, you can achieve an even higher/lower consistency level with the quorum commit (trade-off with availability).

For example, to have any 2 replicas to confirm a commit: 

```bash
pg-test:
  hosts:
    10.10.10.10: { pg_seq: 1, pg_role: primary } # <--- pg-test-1
    10.10.10.11: { pg_seq: 2, pg_role: replica } # <--- pg-test-2
    10.10.10.12: { pg_seq: 3, pg_role: replica } # <--- pg-test-3
    10.10.10.13: { pg_seq: 4, pg_role: replica } # <--- pg-test-4
  vars:
    pg_cluster: pg-test
    pg_conf: crit.yml   # <--- use crit template
```

Adjust  [`synchronous_standby_names`](https://www.postgresql.org/docs/current/runtime-config-replication.html#synchronous_standby_names) and `synchronous_node_count` accordingly:
* `synchronous_standby_names = ANY 2 (pg-test-2, pg-test-3, pg-test-4)`
* `synchronous_node_count : 2`

<details><summary>Example: Enable Quorum Commit</summary>

```bash
$ pg edit-config pg-test
---
+++
@@ -82,10 +82,12 @@
     work_mem: 4MB
+    synchronous_standby_names: 'ANY 2 (pg-test-2, pg-test-3, pg-test-4)'
 
-synchronous_mode: false
+synchronous_mode: true
+synchronous_node_count: 2
 synchronous_mode_strict: false

Apply these changes? [y/N]: y
```

After the application, the configuration takes effect, and two Sync Standby appear. When the cluster has Failover or expansion and contraction, please adjust these parameters to avoid service unavailability.

```bash
+ Cluster: pg-test (7080814403632534854) +---------+----+-----------+-----------------+
| Member    | Host        | Role         | State   | TL | Lag in MB | Tags            |
+-----------+-------------+--------------+---------+----+-----------+-----------------+
| pg-test-1 | 10.10.10.10 | Leader       | running |  1 |           | clonefrom: true |
| pg-test-2 | 10.10.10.11 | Sync Standby | running |  1 |         0 | clonefrom: true |
| pg-test-3 | 10.10.10.12 | Sync Standby | running |  1 |         0 | clonefrom: true |
| pg-test-4 | 10.10.10.13 | Replica      | running |  1 |         0 | clonefrom: true |
+-----------+-------------+--------------+---------+----+-----------+-----------------+
```

</details>





----------------

## Standby Cluster

You can clone an existing cluster and create a [standby cluster](#standby-cluster), which can be used for migration, horizontal split, multi-az deployment, or disaster recovery.

A standby cluster's definition is just the same as any other normal cluster, except there's a [`pg_upstream`](PARAM#pg_upstream) defined on the primary instance.

For example, you have a `pg-test` cluster, to create a standby cluster `pg-test2`, the inventory may look like this: 

```yaml
# pg-test is the original cluster
pg-test:
  hosts:
    10.10.10.11: { pg_seq: 1, pg_role: primary }
  vars: { pg_cluster: pg-test }

# pg-test2 is a standby cluster of pg-test.
pg-test2:
  hosts:
    10.10.10.12: { pg_seq: 1, pg_role: primary , pg_upstream: 10.10.10.11 } # <--- pg_upstream is defined here
    10.10.10.13: { pg_seq: 2, pg_role: replica }
  vars: { pg_cluster: pg-test2 }
```

And `pg-test2-1`, the primary of `pg-test2` will be a replica of `pg-test` and serve as a **Standby Leader** in `pg-test2`.

Just make sure that the [`pg_upstream`](/en/docs/pgsql/config#pg_upstream) parameter is configured on the primary of the backup cluster to pull backups from the original upstream automatically.

```bash
bin/pgsql-add pg-test     # Creating the original cluster
bin/pgsql-add pg-test2    # Creating a Backup Cluster
```


<details><summary>Example: Change Replication Upstream</summary>

You can change the replication upstream of the standby cluster when necessary (e.g. upstream failover).

To do so, just change the `standby_cluster.host` to the new upstream IP address and apply.

```bash
$ pg edit-config pg-test2

 standby_cluster:
   create_replica_methods:
   - basebackup
-  host: 10.10.10.13     # <--- The old upstream
+  host: 10.10.10.12     # <--- The new upstream
   port: 5432

 Apply these changes? [y/N]: y
```

</details>



<details><summary>Example: Promote Standby Cluster</summary>

You can promote the standby cluster to a standalone cluster at any time.

To do so, you have to [config](PGSQL-ADMIN#config-cluster) the cluster and wipe the entire `standby_cluster` section then apply.

```bash
$ pg edit-config pg-test2
-standby_cluster:
-  create_replica_methods:
-  - basebackup
-  host: 10.10.10.11
-  port: 5432

Apply these changes? [y/N]: y
```

</details>



<details><summary>Example: Cascade Replica</summary>

If the [`pg_upstream`](PARAM#pg_upstream) is specified for **replica** rather than **primary**, the replica will be configured as a cascade replica with the given upstream ip instead of the cluster primary

```yaml
pg-test:
  hosts: # pg-test-1 ---> pg-test-2 ---> pg-test-3
    10.10.10.11: { pg_seq: 1, pg_role: primary }
    10.10.10.12: { pg_seq: 2, pg_role: replica } # <--- bridge instance
    10.10.10.13: { pg_seq: 2, pg_role: replica, pg_upstream: 10.10.10.12 } 
    # ^--- replicate from pg-test-2 (the bridge) instead of pg-test-1 (the primary) 
  vars: { pg_cluster: pg-test }
```

</details>





----------------

## Delayed Cluster

A delayed cluster is a special type of standby cluster, which is used to recover "drop-by-accident" ASAP.

For example, if you wish to have a cluster `pg-testdelay` which has the same data as 1-day ago `pg-test` cluster:

```yaml
# pg-test is the original cluster
pg-test:
  hosts:
    10.10.10.11: { pg_seq: 1, pg_role: primary }
  vars: { pg_cluster: pg-test }

# pg-testdelay is a delayed cluster of pg-test.
pg-testdelay:
  hosts:
    10.10.10.12: { pg_seq: 1, pg_role: primary , pg_upstream: 10.10.10.11, pg_delay: 1d }
    10.10.10.13: { pg_seq: 2, pg_role: replica }
  vars: { pg_cluster: pg-test2 }
```

You can also [configure](PGSQL-ADMIN#config-cluster) a replication delay on the existing [standby cluster](#standby-cluster). 

```bash
$ pg edit-config pg-testdelay
 standby_cluster:
   create_replica_methods:
   - basebackup
   host: 10.10.10.11
   port: 5432
+  recovery_min_apply_delay: 1h    # <--- add delay here

Apply these changes? [y/N]: y
```

When some tuples & tables are dropped by accident, you can advance this delayed cluster to a proper time point and select data from it.

It takes more resources, but can be much faster and have less impact than [PITR](PGSQL-PITR)






----------------

## Citus Cluster

Pigsty has native citus support. Check [`files/pigsty/citus.yml`](https://github.com/Vonng/pigsty/blob/master/files/pigsty/citus.yml) for example.

TBD for patroni 3.0 citus native support