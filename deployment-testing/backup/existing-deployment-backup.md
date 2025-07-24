# 现有部署备份信息

## 备份时间
- **日期**: 2025-07-24
- **目的**: 在更新到2数据库设计前备份现有1数据库部署

## 现有CloudFormation栈信息
- **栈名称**: `payer-athena-final-1753230578`
- **状态**: CREATE_COMPLETE
- **创建时间**: 2025-07-23T00:29:39.623000+00:00
- **模板描述**: "Setup Athena environment for CUR data analysis - supports both Pro forma and RISP CUR"

## 现有输出
- **DatabaseName**: `athenacurcfn_730335480018`
- **ProformaCrawlerName**: `AWSCURCrawler-730335480018`
- **RISPCrawlerName**: `AWSRISPCURCrawler-730335480018`

## 现有数据库和表
### 数据库: `athenacurcfn_730335480018`
- **描述**: Database for CUR data analysis - Account 730335480018
- **表1**: `cost_and_usage_data_status`
  - **位置**: s3://bip-risp-cur-730335480018/daily/risp-730335480018/cost_and_usage_data_status/
- **表2**: `risp_730335480018`
  - **位置**: s3://bip-risp-cur-730335480018/daily/risp-730335480018/risp-730335480018/

## 注意事项
1. 现有设计为1数据库设计，所有数据在单个数据库中
2. 目前只有RISP数据表，缺少Pro forma数据
3. 需要保留此配置作为回滚参考

## 相关的其他栈
- **Billing Conductor**: `payer-billing-conductor-1753182274`
- **RISP CUR**: `payer-cur-risp-1753182831`
- **CloudFront监控**: `payer-cloudfront-monitoring-1753249885`
- **账户管理**: `payer-account-auto-management-v2-1753249437`