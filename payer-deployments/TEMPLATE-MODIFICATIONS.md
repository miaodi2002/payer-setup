# 模板修改记录

## 2025-07-28 模板优化

### 1. BillingGroup自动账号关联

**文件**: `aws-payer-automation/templates/02-billing-conductor/billing_conductor.yaml`

**修改内容**: 在创建BillingGroup时启用自动账号关联功能

**修改位置**:
1. 主要创建参数 (第396-399行):
```python
'AccountGrouping': {
    'LinkedAccountIds': [primary_account_id],
    'AutoAssociate': True  # 启用自动账号关联
},
```

2. 备用创建方式 (第443-446行):
```python
AccountGrouping={
    'LinkedAccountIds': [primary_account_id],
    'AutoAssociate': True  # 启用自动账号关联
},
```

**效果**: 
- 新账号创建后会自动关联到BillingGroup "Bills"
- 不需要手动添加新账号到BillingGroup
- 简化了新账号的计费管理流程

### 2. CUR导出关闭Resource IDs

**文件1**: `aws-payer-automation/templates/03-cur-proforma/cur_export_proforma.yaml`
**文件2**: `aws-payer-automation/templates/04-cur-risp/cur_export_risp.yaml`

**修改内容**: 关闭CUR报告中的Include resource IDs选项

**修改位置**:
- cur_export_proforma.yaml (第318行):
```python
'AdditionalSchemaElements': [],  # 关闭Include resource IDs
```

- cur_export_risp.yaml (第239行):
```python
'AdditionalSchemaElements': [],  # 关闭Include resource IDs
```

**效果**:
- 减少CUR报告的数据量和复杂度
- 提高查询性能
- 降低S3存储成本
- 如果后续需要resource IDs，可以重新添加'RESOURCES'

## 部署说明

1. 这些修改会在下次部署新Payer时自动生效
2. 对于已存在的Payer：
   - BillingGroup自动关联需要在AWS控制台手动启用
   - CUR设置需要重新创建报告或修改现有报告设置

## 验证方法

### 验证BillingGroup自动关联:
```bash
# 创建新账号后，检查BillingGroup成员
aws billingconductor list-accounts-associated-with-billing-group \
    --billing-group-arn <billing-group-arn>
```

### 验证CUR设置:
```bash
# 检查CUR报告定义
aws cur describe-report-definitions --region us-east-1
# 查看AdditionalSchemaElements是否为空数组
```