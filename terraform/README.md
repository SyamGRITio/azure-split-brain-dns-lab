# Terraform版

[ルートREADMEへ戻る](../README.md)

## 事前準備

- Terraform `1.16.x`
- Azure CLIでAzureへログイン済み
- Azureリソースを作成できる権限
- SSH公開鍵
- 自分で管理し、Public DNSを変更できるカスタムドメイン

使用するサブスクリプションを設定します。

```bash
az login
az account set --subscription "<サブスクリプションIDまたは名前>"
export ARM_SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
export ARM_TENANT_ID="$(az account show --query tenantId --output tsv)"
```

`local.tf`を自分の環境に合わせて変更します。

```hcl
locals {
  resource_group_name = "<リソースグループ名>"
  region              = "japaneast"
  ssh_public_key_path = "~/.ssh/id_rsa.pub"
  my_custom_domain    = "example.com"
}
```

初級編のStorage Accountも作成する場合は、次の値を`true`にします。

```hcl
enable_split_brain_dns_beginner = true
```

## デプロイ

Public DNSの手動設定とマネージド証明書の発行を挟むため、`base → certificate → private`の順に進めます。

```bash
terraform init
terraform validate

terraform plan -var='deployment_phase=base' -out='base.tfplan'
terraform apply "base.tfplan"
```

ここでContainer Apps環境のStatic IP、Container Appの生成FQDN、Custom Domain Verification IDを確認し、XserverへA・CNAME・TXTレコードを登録します。レコードの内容は[中級編の記事](https://zenn.dev/gritio28tech/articles/441d92f09287b8)を参照してください。

```bash
terraform plan -var='deployment_phase=certificate' -out='certificate.tfplan'
terraform apply -parallelism=1 "certificate.tfplan"

terraform plan -var='deployment_phase=private' -out='private.tfplan'
terraform apply "private.tfplan"
```

## 動作確認

検証用VMには次のコマンドで接続します。

```bash
az ssh vm --resource-group <リソースグループ名> --name vm-dev-ssh --local-user azureuser
```

名前解決とHTTPS接続の確認内容は、[初級編](https://zenn.dev/gritio28tech/articles/d60ab47c81934f)と[中級編](https://zenn.dev/gritio28tech/articles/441d92f09287b8)に掲載しています。最後に差分がないことを確認します。

```bash
terraform plan -var='deployment_phase=private'
```

## 削除

```bash
terraform destroy -var='deployment_phase=private'
terraform state list
```

`terraform state list`で何も表示されなければ削除完了です。

## IaC化で工夫したこと

- コードをコメントアウトせず、`deployment_phase`だけで3段階の構成を切り替えられるようにしました。
- IPアドレス、SSH公開鍵、Azureのログイン情報は、Data Sourceや`file()`から取得しています。
- マネージド証明書を削除する前にカスタムドメインとの紐付けを解除し、`CertificateInUse`を避けて一度の`terraform destroy`で削除できるようにしました。

## 使って感じたこと

個人的にはBicepよりコードの可読性が高く、`plan`の差分から何が変わるのかを追いやすいと感じました。既存リソースをimportし、`-generate-config-out`で出力したコードを調整できるため、実物を起点にIaC化しやすい点も便利でした。

今回面倒だったのは、証明書を削除する前にカスタムドメインとのバインドを解除する処理が必要だった点です。そのため、AzureRM Providerを基本にしつつ、標準的な作成・参照・更新・削除に収まらない処理をAzAPIのPATCHで補いました。手間はかかりましたが、これは[AzureRMに足りない操作をAzAPIで補う使い分け](https://learn.microsoft.com/ja-jp/azure/developer/terraform/provider-selection-azurerm-vs-azapi)なので、Terraformの大きなデメリットとは感じていません。
