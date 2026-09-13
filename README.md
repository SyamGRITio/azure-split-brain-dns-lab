# azure-split-brain-dns-lab

Zennの[初級編（Storage Account）](https://zenn.dev/gritio28tech/articles/d60ab47c81934f)と[中級編（Azure Container Appsのカスタムドメイン）](https://zenn.dev/gritio28tech/articles/441d92f09287b8)で検証した、Azure Private Endpointとsplit-brain DNSの構成をIaCで再現するリポジトリです。

Terraform版とBicep版を用意しています。

- [Terraform版の使い方](./terraform/README.md)
- [Bicep版の使い方](./bicep/README.md)

## 検証構成

### 初級編：Storage Account

Azureサービスの既定FQDNが、VNet内外で異なるIPアドレスへ名前解決される基本動作を確認します。

```mermaid
flowchart LR
  pc["VNet外のPC"]
  publicDns["AzureのPublic DNS<br/>Storage AccountのFQDN → CNAME<br/>privatelink.* → Public IP"]

  subgraph azure["Microsoft Azure"]
    privateDns["Private DNS Zone<br/>privatelink.blob.core.windows.net<br/>privatelink.* → Private IP"]

    subgraph vnet["Virtual Network"]
      vm["検証用VM"]
      pe["Private Endpoint<br/>Private IP"]
    end

    storage["Storage Account<br/>Public Network Access：無効"]
  end

  pc -. "Public DNSで名前解決" .-> publicDns
  pc -. "az ssh（管理接続）" .-> vm
  pc -- "HTTPS：× 接続不可" --> storage
  vm -. "Private DNSで名前解決<br/>Virtual Network Link" .-> privateDns
  vm -- "HTTPS" --> pe
  pe -- "Private Link" --> storage

  linkStyle 2 stroke:#d13438,color:#d13438
```

### 中級編：Azure Container Appsのカスタムドメイン

カスタムドメインのapexとサブドメインを扱い、同名のPrivate DNS Zoneが必要になる構成を確認します。

```mermaid
flowchart LR
  pc["VNet外のPC"]
  publicDns["XserverのPublic DNS<br/>apex：A → Public IP<br/>www：CNAME → ACAの生成FQDN"]

  subgraph azure["Microsoft Azure"]
    customDns["Private DNS Zone<br/>syam-gritio.com<br/>apex：A → Private IP<br/>www：CNAME → ACAの生成FQDN"]
    privateLinkDns["Private DNS Zone<br/>privatelink.japaneast.azurecontainerapps.io<br/>privatelink.* → Private IP"]

    subgraph vnet["Virtual Network"]
      vm["検証用VM"]
      pe["Private Endpoint<br/>Private IP"]
    end

    aca["Azure Container Apps<br/>Public Network Access：無効"]
  end

  pc -. "Public DNSで名前解決" .-> publicDns
  pc -. "az ssh（管理接続）" .-> vm
  pc -- "HTTPS：× 接続不可" --> aca
  vm -. "Private DNSで名前解決<br/>Virtual Network Link" .-> customDns
  customDns -. "www：ACAの生成FQDN → privatelink.*" .-> privateLinkDns
  vm -- "HTTPS" --> pe
  pe -- "Private Link" --> aca

  linkStyle 2 stroke:#d13438,color:#d13438
```

## TerraformとBicepを使った感想

今回の構成を両方で作成・削除した、個人的な感想です。

| 観点 | Terraform | Bicep |
| --- | --- | --- |
| 差分確認 | `plan`で確認したい変更を追いやすい | What-Ifのノイズが多く、変更点が埋もれやすい |
| 既存環境のIaC化 | importと`-generate-config-out`を起点にコードを調整できる | Portalから取得したテンプレートをそのまま使えない場合がある |
| 状態管理 | stateの管理が必要 | stateやimportが不要 |
| 証明書のバインド | AzAPIで紐付けと解除を実装した | `bindingType: 'Auto'`で自動化できた |
| 削除 | `terraform destroy`でまとめて削除できる | 今回はリソースグループごと削除する |
| 今回の印象 | コードと差分を読みやすく、検証を進めやすかった | 関係のない既存リソースも再評価される点が不便だった |

個人的には、Microsoft製品中心の企業でも、人の入れ替わりがある現場では、共通言語にしやすいTerraformでインフラIaCを書く方がよいと改めて思いました。

今回Bicepに軍配が上がったと感じたのは、マネージド証明書とカスタムドメインのバインドを`Auto`にできた点です。stateやimportが不要な点と、ARM APIのバージョンを直接指定できる点も利点ですが、今回は大きな恩恵を実感しませんでした。

## 検証費用

![Azureの検証費用](./docs/images/azure-cost-example.png)

今回はすべてのリソースを数時間ずつ稼働させながら、1日で初級編・中級編の検証を行い、費用は約323円でした。構成や稼働時間によって変わりますが、1日で検証する場合は200〜300円台が目安です。

## ディレクトリ構成

```text
.
├── terraform/          # Terraform版と固有のREADME
├── bicep/              # Bicep版、パラメーターファイル、固有のREADME
├── docs/images/        # READMEで使用する画像
├── README.md
└── LICENSE
```

Public DNSはXserver Domainで手動設定します。IaCの管理対象には含まれないため、検証後はAzureリソースだけでなく、不要になったPublic DNSレコードも削除してください。
