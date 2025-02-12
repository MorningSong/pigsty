# File Hierarchy Structure

> How files are organized in Pigsty.

## Pigsty FHS

```bash
#------------------------------------------------------------------------------
# pigsty
#  ^-----@app                    # extra demo application resources
#  ^-----@bin                    # bin scripts
#  ^-----@docs                   # document (can be docsified)
#  ^-----@files                  # ansible file resources 
#            ^-----@pigsty       # pigsty config template files
#            ^-----@prometheus   # prometheus rules definition
#            ^-----@grafana      # grafana dashboards
#            ^-----@postgres     # /pg/bin/ scripts
#            ^-----@migration    # pgsql migration task definition
#            ^-----@pki          # self-signed CA & certs

#  ^-----@roles                  # ansible business logic
#  ^-----@templates              # ansible templates
#  ^-----@vagrant                # sandbox resources
#  ^-----configure               # configure wizard script
#  ^-----ansible.cfg             # default ansible config file
#  ^-----pigsty.yml              # default config file
#  ^-----*.yml                   # ansible playbooks

#------------------------------------------------------------------------------
# /etc/pigsty/
#  ^-----@targets                # file based service discovery targets definition
#  ^-----@dashboards             # static grafana dashboards
#  ^-----@datasources            # static grafana datasource
#  ^-----@playbooks              # extra ansible playbooks
#------------------------------------------------------------------------------
```



## CA FHS

Pigsty's self-signed CA is located on `files/pki/` directory under pigsty home.

```bash
# pigsty/files/pki
#  ^-----@ca                      # self-signed CA key & cert
#         ^-----@ca.key           # VERY IMPORTANT: keep it secret
#         ^-----@ca.crt           # VERY IMPORTANT: trusted everywhere
#  ^-----@csr                     # signing request csr
#  ^-----@misc                    # misc certs, issued certs
#  ^-----@etcd                    # etcd server certs
#  ^-----@minio                   # minio server certs
#  ^-----@nginx                   # nginx SSL certs
#  ^-----@infra                   # infra client certs
#  ^-----@pgsql                   # pgsql server certs
```



## Prometheus FHS

```bash
#------------------------------------------------------------------------------
# Config FHS
#------------------------------------------------------------------------------
# /etc/prometheus/
#  ^-----prometheus.yml              # prometheus main config file
#  ^-----@bin                        # util scripts: check,reload,status,new
#  ^-----@rules                      # record & alerting rules definition
#            ^-----@infra            # infrastructure rules & alert
#            ^-----@node             # nodes rules & alert
#            ^-----@pgsql            # pgsql rules & alert
#            ^-----@redis            # redis rules & alert
#            ^-----@..........       # etc...
#  ^-----@targets                    # file based service discovery targets definition
#            ^-----@infra            # infra static targets definition
#            ^-----@node             # nodes static targets definition
#            ^-----@etcd             # etcd static targets definition
#            ^-----@minio            # minio static targets definition
#            ^-----@ping             # blackbox ping targets definition
#            ^-----@pgsql            # pgsql static targets definition
#            ^-----@redis            # redis static targets definition
#            ^-----@.....            # other targets
# /etc/alertmanager.yml              # alertmanager main config file
# /etc/blackbox.yml                  # blackbox exporter main config file
#------------------------------------------------------------------------------
```



## Postgres FHS

The following parameters are related to the PostgreSQL database dir:

* [pg_dbsu_home](PARAM#pg_dbsu_home): Postgres default user's home dir, default is `/var/lib/pgsql`.
* [pg_bin_dir](PARAM#pg_bin_dir): Postgres binary dir, defaults to `/usr/pgsql/bin/`.
* [pg_data](PARAM#pg_data): Postgres database dir, default is `/pg/data`.
* [pg_fs_main](PARAM#pg_fs_main): Postgres main data disk mount point, default is `/data`.
* [pg_fs_bkup](PARAM#pg_fs_bkup): Postgres backup disk mount point, default is `/data/backups` (used when using local backup repo).

```yaml
#--------------------------------------------------------------#
# Create Directory
#--------------------------------------------------------------#
# assumption:
#   {{ pg_fs_main }} for main data   , default: `/data`              [fast ssd]
#   {{ pg_fs_bkup }} for backup data , default: `/data/backups`     [cheap hdd]
#--------------------------------------------------------------#
# default variable:
#     pg_fs_main = /data             fast ssd
#     pg_fs_bkup = /data/backups     cheap hdd (optional)
#
#     /pg      -> /data/postgres/pg-test-15    (soft link)
#     /pg/data -> /data/postgres/pg-test-15/data
#--------------------------------------------------------------#
- name: create postgresql directories
  tags: pg_dir
  become: yes
  block:

    - name: make main and backup data dir
      file: path={{ item }} state=directory owner=root mode=0777
      with_items:
        - "{{ pg_fs_main }}"
        - "{{ pg_fs_bkup }}"

    # pg_cluster_dir:    "{{ pg_fs_main }}/postgres/{{ pg_cluster }}-{{ pg_version }}"
    - name: create postgres directories
      file: path={{ item }} state=directory owner={{ pg_dbsu }} group=postgres mode=0700
      with_items:
        - "{{ pg_fs_main }}/postgres"
        - "{{ pg_cluster_dir }}"
        - "{{ pg_cluster_dir }}/bin"
        - "{{ pg_cluster_dir }}/log"
        - "{{ pg_cluster_dir }}/tmp"
        - "{{ pg_cluster_dir }}/cert"
        - "{{ pg_cluster_dir }}/conf"
        - "{{ pg_cluster_dir }}/data"
        - "{{ pg_cluster_dir }}/meta"
        - "{{ pg_cluster_dir }}/stat"
        - "{{ pg_cluster_dir }}/change"
        - "{{ pg_backup_dir }}/backup"
```


**Data FHS**

```bash
# basic
{{ pg_fs_main }}     /data                      # top level data directory, usually a SSD mountpoint
{{ pg_dir_main }}    /data/postgres             # contains postgres data
{{ pg_cluster_dir }} /data/postgres/pg-test-15  # contains cluster `pg-test` data (of version 13)
                     /data/postgres/pg-test-15/bin            # bin scripts
                     /data/postgres/pg-test-15/log            # logs: postgres/pgbouncer/patroni/pgbackrest
                     /data/postgres/pg-test-15/tmp            # tmp, sql files, rendered results
                     /data/postgres/pg-test-15/cert           # postgres server certificates
                     /data/postgres/pg-test-15/conf           # patroni config, links to related config
                     /data/postgres/pg-test-15/data           # main data directory
                     /data/postgres/pg-test-15/meta           # identity information
                     /data/postgres/pg-test-15/stat           # stats information, summary, log report
                     /data/postgres/pg-test-15/change         # changing records
                     /data/postgres/pg-test-15/backup         # soft link to backup dir

{{ pg_fs_bkup }}     /data/backups                            # could be a cheap & large HDD mountpoint
                     /var/backups/postgres/pg-test-15/backup  # local backup repo path

# links
/pg             ->   /data/postgres/pg-test-15                # pg root link
/pg/data        ->   /data/postgres/pg-test-15/data           # real data dir
/pg/backup      ->   /var/backups/postgres/pg-test-15/backup  # base backup
```


**Binary FHS**

On EL releases, the default path for PostgreSQL bin is:

```bash
/usr/pgsql-${pg_version}/
```

Pigsty will create a softlink `/usr/pgsql` to the currently installed version specified by [`pg_version`](PARAM#pg_version).

```bash
/usr/pgsql -> /usr/pgsql-15
```

Therefore, the default [`pg_bin_dir`](PARAM#pg_bin_dir) will be `/usr/pgsql/bin/`, and this path is added to the `PATH` environment via `/etc/profile.d/pgsql.sh`.

```bash
export PATH="/usr/pgsql/bin:/pg/bin:$PATH"
export PGHOME=/usr/pgsql
export PGDATA=/pg/data
```





## Pgbouncer FHS

Pgbouncer is run using the Postgres user, and the config file is located in `/etc/pgbouncer`. The config file includes.

* `pgbouncer.ini`: pgbouncer main config
* `database.txt`: pgbouncer database list
* `userlist.txt`: pgbouncer user list
* `useropts.txt`: pgbouncer user options (user-level parameter overrides)
* `pgb_hba.conf`: lists the access privileges of the connection pool users





## Redis FHS

Pigsty provides essential support for Redis deployment and monitoring.

Redis binaries are installed in `/bin/` using RPM-packages or copied binaries, including:

```bash
redis-server    
redis-server    
redis-cli       
redis-sentinel  
redis-check-rdb 
redis-check-aof 
redis-benchmark 
/usr/libexec/redis-shutdown
```

For a Redis instance named `redis-test-1-6379`, the resources associated with it are shown below:

```bash
/usr/lib/systemd/system/redis-test-1-6379.service               # Services
/etc/redis/redis-test-1-6379.conf                               # Config 
/data/redis/redis-test-1-6379                                   # Database Catalog
/data/redis/redis-test-1-6379/redis-test-1-6379.rdb             # RDB File
/data/redis/redis-test-1-6379/redis-test-1-6379.aof             # AOF file
/var/log/redis/redis-test-1-6379.log                            # Log
/var/run/redis/redis-test-1-6379.pid                            # PID
```

