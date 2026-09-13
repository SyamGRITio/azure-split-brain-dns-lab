# Bicep版

[ルートREADMEへ戻る](../README.md)

## ファイル構成

```text
bicep/
├── main.bicep                         # リソースグループとモジュール呼び出し
├── resources.bicep                    # Azureリソース本体
└── parameters/
    ├── beginner/
    │   └── beginner.bicepparam        # 中級編の最終構成に初級編を追加
    └── intermediate/
        ├── base.bicepparam
        ├── certificate.bicepparam
        └── private.bicepparam
```

## 事前準備

- Azure CLIとBicep CLI
- Azureリソースを作成できる権限
- SSH公開鍵
- 自分で管理し、Public DNSを変更できるカスタムドメイン

使用するサブスクリプションと、ローカル環境から渡す値を設定します。

```bash
az login
az account set --subscription "<サブスクリプションIDまたは名前>"

export MY_IP="$(curl -s https://api.ipify.org)/32"
export SSH_KEY="$(tr -d '\r\n' < ~/.ssh/id_rsa.pub)"
```

`main.bicep`のリソースグループ名とリージョン、各`.bicepparam`の`customDomainName`を自分の環境に合わせて変更します。

```bicep
param customDomainName = 'example.com'
```

`.bicepparam`に保存されるのは環境変数名だけで、SSH公開鍵や自宅IPの実値はリポジトリに保存されません。

## デプロイ

Public DNSの手動設定とマネージド証明書の発行を挟むため、中級編は`base → certificate → private`の順に進めます。

`-l`はサブスクリプションスコープのデプロイ履歴を保存する場所、`-p`はBicepへ渡すパラメーターファイルです。親デプロイ名は既定の`main`を使用し、リソースグループ側の履歴は`main.bicep`のモジュール名によって`deploy-resources-base`などに分かれます。

```bash
az deployment sub create -l japaneast \
  -p parameters/intermediate/base.bicepparam
```

ここでContainer Apps環境のStatic IP、Container Appの生成FQDN、Custom Domain Verification IDを確認し、XserverへA・CNAME・TXTレコードを登録します。レコードの内容は[中級編の記事](https://zenn.dev/gritio28tech/articles/441d92f09287b8)を参照してください。

```bash
az deployment sub create -l japaneast \
  -p parameters/intermediate/certificate.bicepparam

az deployment sub create -l japaneast \
  -p parameters/intermediate/private.bicepparam
```

初級編のStorage Accountも追加する場合は、次のパラメーターファイルを使用します。

```bash
az deployment sub create -l japaneast \
  -p parameters/beginner/beginner.bicepparam
```

実行前に差分を確認する場合は、`create`を`what-if`へ置き換えます。

## 動作確認

検証用VMには次のコマンドで接続します。

```bash
az ssh vm --resource-group <リソースグループ名> --name vm-dev-ssh --local-user azureuser
```

名前解決とHTTPS接続の確認内容は、[初級編](https://zenn.dev/gritio28tech/articles/d60ab47c81934f)と[中級編](https://zenn.dev/gritio28tech/articles/441d92f09287b8)に掲載しています。

## 削除

Bicepには`terraform destroy`に相当するコマンドがないため、今回の検証ではリソースグループごと削除します。

```bash
az group delete --name <リソースグループ名> --yes --no-wait
az group wait --name <リソースグループ名> --deleted
```

## IaC化で工夫したこと

- `.bicepparam`を初級編・中級編と作成段階ごとに分け、ファイルの選択だけで構成を切り替えられるようにしました。
- デプロイ名に`base`、`certificate`、`private`を含め、Azure Portalからどの段階を実行したのか分かるようにしました。
- SSH公開鍵と自宅IPは環境変数から受け取り、個人の値を公開リポジトリへ含めないようにしました。
- `bindingType: 'Auto'`を利用し、マネージド証明書をカスタムドメインへバインドしています。

## 使って感じたこと

Bicepはstateやimportが不要で、ARM APIのバージョンをリソースごとに直接指定できます。今回明確に良いと感じたのは、`bindingType: 'Auto'`でマネージド証明書とカスタムドメインを自動でバインドできた点です。それ以外は、今回の検証ではTerraformと比べて大きなメリットを感じませんでした。

What-Ifには今回変更していないプロパティも多数表示され、確認したい差分が埋もれやすく感じました。Private Endpointを追加したいだけでもVMが再評価され、SSH公開鍵の違いによってデプロイ全体が失敗したこともあります。

また、`main.bicep`から`resources.bicep`へ同じパラメーターを明示的に受け渡すため、書いた本人には分かっても、初めて読む人には値の流れが追いづらいと感じました。Azure Portalから取得したテンプレートも、そのまま利用できるとは限らず、コードを書く根拠を見つけづらかった点も不便でした。
