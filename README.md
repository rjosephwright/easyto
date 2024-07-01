# easyto

If you have a container image that you want to run directly on EC2, then easyto is for you. It builds an EC2 AMI from a container image.

## How does it work?

It creates a temporary EC2 AMI build instance[^1] with an EBS volume attached. The EBS volume is partitioned and formatted, and the container image layers are written to the main partition. Then a Linux kernel, bootloader, and custom init and utilities are added. The EBS volume is then snapshotted and an AMI is created from it.

The `metadata.json` from the container image is written into the AMI so init will know what command to start on boot, and behave as specified in the Dockerfile. The command can be overridden, much like you can with docker or Kubernetes. This is accomplished with a custom [EC2 user data](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-add-user-data.html) format [defined below](#user-data) that is intended to be similar to a Kubernetes pod definition.

## Installing

Download the release and unpack it. The `easyto` binary lives in the `bin` subdirectory and runs directly from there.

## Building an image

First make sure your AWS credentials and region are in scope, for example:

```
export AWS_PROFILE=xyz
export AWS_REGION=us-east-1
```

To create an AMI called `postgres-16.2-bullseye` from the `postgres:16.2-bullseye` image on Docker Hub that includes both chrony and ssh services, run:

```
easyto -a postgres-16.2-bullseye -c postgres:16.2-bullseye --services chrony,ssh -s subnet-e358acdfe25b8fb3b
```

The subnet option tells it where to put the temporary build instance.

For the help menu, run:

```
easyto --help
```

## Running an instance

Instances are created "the usual way" with the AWS console, AWS CLI, or Terraform, for example. Modifying the startup configuration is different from other EC2 instances however, because the user data format is different. The AMIs are not configured to use [cloud-init](https://cloudinit.readthedocs.io/en/latest/index.html), and putting a shell script into user data will not work.

### User data

The user data format is meant to be similar to a container configuration, and borrows nomenclature from the Kubernetes pod spec.

Example:

```
env-from:
  - ssm-parameter:
      path: /postgres
volumes:
  - ebs:
      device: /dev/sdb
      fs-type: ext4
      make-fs: true
      mount:
        directory: /var/lib/postgresql
```

The full specification is as follows:

`args`: (Optional, type _list of string_, see description for default value) - Arguments to `command`. If `args` is not defined in user data, it defaults to the container image [cmd](https://docs.docker.com/reference/dockerfile/#cmd), unless `command` is defined in user data, in which case it defaults to an empty list.

`command`: (Optional, type _list of string_, default is the image [entrypoint](https://docs.docker.com/reference/dockerfile/#entrypoint)) - Override of the image's entrypoint.

`debug`: (Optional, type _bool_, default `false`) - Whether or not to enable debug logging.

`disable-services`: (Optional, type _list of _string_, default `[]`) - A list of services to disable at runtime. Note that this has no effect if the image was built with the services disabled.

`env`: (Optional, type _list_ of [_name-value_](#name-value-object) objects, default `[]`) - The names and values of environment variables to be passed to `command`.

`env-from`: (Optional, type _list_ of [_env-from_](#env-from-object) objects, default `[]`) - Environment variables to be passed to `command`, to be retrieved from the given sources.

`replace-init`: (Optional, type _bool_, default `false`) - If `true`, `command` will replace init when executed. This may be useful if you want to run your own init process. However, easyto init will still do everything leading up to the execution of `command`, for example formatting and mounting filesystems defined in `volumes` and setting environment variables.

`security`: (Optional, type [_security_](#security-object) object, default `{}`) - Configuration of security settings.

`shutdown-grace-period`: (Optional, type _int_, default `10`) - When shutting down, the number of seconds to wait for all processes to exit cleanly before sending a kill signal.

`sysctls`: (Optional, type _list_ of [_name-value_](#name-value-object) objects, default `[]`) - The names and values of sysctls to set before starting `command`.

`volumes`: (Optional, type _list_ of [_volume_](#volume-object) objects, default `[]`) - Configuration of volumes.

#### name-value object

`name`: (Required, type _string_) - Name of item.

`value`: (Required, type _string_) - Value of item.

#### env-from object

Note that currently only the SSM Parameter source is defined but others are planned.

`ssm-parameter`: (Optional, type [_ssm-parameter-env_](#ssm-parameter-env-object) object) - Configuration for SSM Parameter environment source.

#### ssm-parameter-env object

`path`: (Required, type _string_) - The SSM Parameter path, which must begin with `/`. Everything under this path one level deep will be retrieved. Nested parameters are ignored. The names of the parameters under the path will be the names of the environment variables. For example, if you want your instance to have environment variables `PGHOST` and `PGPASSWORD`, given a `path` of `/postgres`, you would create the SSM parameters `/postgres/PGHOST` and `/postgres/PGPASSWORD`.

`optional`: (Optional, type _bool_, default `false`) - Whether or not the parameters are optional. If `false`, then a failure to find the items in SSM Parameter Store will be treated as an error.

#### security object

`readonly-root-fs`: (Optional, type _bool_, default `false`) - Whether or not to mount the root filesystem as readonly.

`run-as-group-id`: (Optional, type _int_, default `0`) - Group ID that `command` should run as.

`run-as-user-id`: (Optional, type _int_, default `0`) - User ID that `command` should run as.

#### volume object

`ebs`: (Optional, type [_ebs-volume_](#ebs-volume-object) object, default `{}`) - Configuration of an EBS volume.

`ssm-parameter`: (Optional, type [_ssm-parameter-volume_](#ssm-parameter-volume-object) object, default `{}`) - Configuration of an SSM Parameter "volume".

`s3`: (Optional, type [_s3-volume_](#s3-volume-object) object, default `{}`) - Configuration of an S3 "volume".

#### ebs-volume object

`device`: (Required, type _string_) - Name of the device as defined in the instance's block device mapping.

`fs-type`: (Required, type _string_) - Filesystem type of the device.

`make-fs`: (Optional, type _bool_, default `true`) - Whether or not to create a filesystem on the device if it does not have one.

`mount`: (Required, type [_mount_](#mount-object) object) - Whether or not to create a filesystem on the device if it does not have one.

`working-dir`: (Optional, type _string_, default `/`) - The directory in which `command` will be run.

#### ssm-parameter-volume object

An SSM Parameter volume is not an actual volume, rather the parameters from SSM Parameter Store are copied as files to the object's `mount.directory` one time on boot. Any updates to the parameters would require a reboot to get the new values. The files are always written with permissions of `0600`, even if the parameters are not of type `SecureString`. The owner and group of the files defaults to `security.run-as-user` and `security.run-as-group` unless explicitly specified in `mount.user-id` and `mount.group-id`.

> [!NOTE]
> The EC2 instance must have an instance profile with permission to call `ssm:GetParametersByPath` and `kms:Decrypt`.

`path`: (Required, type _string_) - The SSM parameter path, which must begin with `/`. Everything under this path in SSM Parameter Store will be retrieved and stored in files named the same as the parameters, omitting the leading `path`. The SSM parameters can be nested; those with child parameters will be used to create directories under the object's `mount.directory`.

> [!NOTE]
> If there are SSM parameters `/abc/xyz` and `/abc/xyz/123`, the file `xyz` will not be written because there cannot be both a file and directory with the same name.

`mount`: (Required, type [_mount_](#mount-object) object) - Configuration of the destination "mount" of the parameters.

`optional`: (Optional, type _bool_, default `false`) - Whether or not the parameters are optional. If `false`, then a failure to fetch the items in SSM Parameter Store will be treated as an error.

#### s3-volume object

Similar to SSM Parameter volumes, S3 volumes are used to copy objects from an S3 bucket as files to the object's `mount.directory` one time on boot. The owner and group of the files defaults to `security.run-as-user` and `security.run-as-group` unless explicitly specified in `mount.user-id` and `mount.group-id`.

> [!NOTE]
> The EC2 instance must have an instance profile with permission to call `s3:GetObject` and `s3:ListObjects`.

`bucket`: (Required, type [_string_]) - Name of the S3 bucket.

`key-prefix`: (Optional, type [_string_], default empty) - Only objects in `bucket` beginning with this prefix will be returned. If not defined, the whole bucket will be copied.

> [!NOTE]
> If there are S3 objects `abc/xyz` and `abc/xyz/123`, the file `xyz` will not be written because there cannot be both a file and directory with the same name.

`mount`: (Required, type [_mount_](#mount-object) object) - Configuration of the destination "mount" of the parameters.

`optional`: (Optional, type _bool_, default `false`) - Whether or not the S3 objects are optional. If `false`, then a failure to fetch the items in S3 will be treated as an error.

#### mount object

`directory`: (Required, type _string_) - The mount directory.

`group-id`: (Optional, type _int_, default `0`) - The group ID of the directory.

`mode`: (Optional, type _string_, default `0755`) - The mode of the directory.

`options`: (Optional, type _list_ of _string_, default `[]`) - Options for filesystem mounting, dependent on the filesystem type.

`user-id`: (Optional, type _int_, default `0`) - The user ID of the directory.

### System services

AMIs can be configured at build time to run additional services on boot. The services available are [chrony](https://chrony-project.org/) and [ssh](https://www.openssh.com/).

To disable all services, use an empty string for services (`--services ""`) when running `easyto`.

#### Chrony

Chrony is included in AMIs by default and is configured to use Amazon's NTP server.

#### SSH

The ssh server is not included in AMIs by default, but can be added with the `--services` option to `easyto`.

If an ssh [key pair](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html) is not specified when creating an EC2 instance from the AMI, the ssh server will not start, even if it is enabled in the AMI.

### Shutdown behavior

The AMIs are configured to behave much like containers. If the main process shuts down for any reason, the instance shutdown procedure is initiated. All child processes and services will stop, filesystems will be unmounted, and the instance will power off.

Shutdown should always result in the instance powering off. EC2 instances will hang for a long time before being terminated if they do not respond, for example if the kernel panics. Easyto init will try to avoid this by powering off in case of intentional shutdowns or errors in the main process.

Similar shutdown behavior should occur if the instance is stopped, rebooted, or terminated from the EC2 API.

## Limitations

* AMIs will be configured with UEFI boot mode, so only instance types that support UEFI boot can be used with them.

* The included utilities are just enough to bootstrap the command. Your container images must add utilities if you plan to ssh into the system.

* Only the amd64 architecture is currently supported.

## Roadmap

* Support arm64 architecture.

* S3 as an environment variable source.

* Additional subcommands.
  * Validate user data.
  * Quick test of an image.

* Support instance store volumes.

[^1]: The Packer [Amazon EBS Surrogate builder](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/builder/ebssurrogate) is used to orchestrate the AMI build.
