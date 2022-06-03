# UEFI対応AMI変換スクリプト

## 概要
BIOS AMIのスナップショットを流用して、UEFI AMIを作成するスクリプトです。

## 注意事項
変換元AMIは下記条件が必要です。条件を満たさないAMIを変換しても起動しません。

- ブートボリュームがGPT形式になっていること
- ESP(EFI System Partition)が存在すること

### 確認方法
利用したいAMIからEC2インスタンスを起動します。起動したら、`gdisk -l`コマンドでパーティション情報を確認します。Partition table scanが`GPT: present`になっていればGPT形式のパーティション構成になっています。Codeが`EF00`(ESP)になっているパーティションが存在すればESPが作成されています。


パーティションがGPT形式でESPパーティションが存在する(UEFI化できる)
```
$ sudo gdisk -l /dev/nvme0n1
GPT fdisk (gdisk) version 1.0.6

Partition table scan:
  MBR: protective
  BSD: not present
  APM: not present
  GPT: present

Found valid GPT with protective MBR; using GPT.
Disk /dev/nvme0n1: 16777216 sectors, 8.0 GiB
Model: Amazon Elastic Block Store
Sector size (logical/physical): 512/512 bytes
Disk identifier (GUID): E4AE2E10-9890-014B-8230-EFEDCE732D4C
Partition table holds up to 128 entries
Main partition table begins at sector 2 and ends at sector 33
First usable sector is 2048, last usable sector is 16777182
Partitions will be aligned on 2048-sector boundaries
Total free space is 0 sectors (0 bytes)

Number  Start (sector)    End (sector)  Size       Code  Name
   1          262144        16777182   7.9 GiB     8300
  14            2048            8191   3.0 MiB     EF02
  15            8192          262143   124.0 MiB   EF00
```

パーティションがMBR形式でESPパーティションが存在しない(UEFI化できない)
```
$ sudo gdisk -l /dev/nvme0n1
GPT fdisk (gdisk) version 1.0.5

Partition table scan:
  MBR: MBR only
  BSD: not present
  APM: not present
  GPT: not present


***************************************************************
Found invalid GPT and valid MBR; converting MBR to GPT format
in memory.
***************************************************************

Disk /dev/nvme0n1: 16777216 sectors, 8.0 GiB
Model: Amazon Elastic Block Store
Sector size (logical/physical): 512/512 bytes
Disk identifier (GUID): 2E25C5E9-766A-47B5-AACA-171FA98860DE
Partition table holds up to 128 entries
Main partition table begins at sector 2 and ends at sector 33
First usable sector is 34, last usable sector is 16777182
Partitions will be aligned on 2048-sector boundaries
Total free space is 2014 sectors (1007.0 KiB)

Number  Start (sector)    End (sector)  Size       Code  Name
   1            2048        16777182   8.0 GiB     8300  Linux filesystem
```

## 使い方
スクリプトに記載されている以下のパラメータを修正します。

- `AMI_OWNER`にベースAMIのOwnerIDを指定(デフォルト値はUbuntu)
- `REGION`にイメージが存在するリージョンを指定(デフォルト値は東京リージョン)
- `AMI_NAME_PREFIX`にベースAMI名のうち、更新されても不変な部分を指定(デフォルト値は`ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-`で、これはUbuntu 22.04イメージに該当。この後の`yyyymmdd`でメジャーバージョン内のバージョンを管理している)

修正したら、スクリプトを実行します。実行すると、下記2種類のイメージが作成されます。
- UEFI_+元のAMI名: ブートモードをUEFIに変更したAMI
- TPM_+元のAMI名: ブートモードをUEFIに変更し、TPMを有効化したAMI
