# RISP CUR "Billable" Data View实现调查报告

## 调查概述

**调查时间**: 2025年7月23日  
**调查目的**: 验证RISP CUR是否正确使用"Billable"数据视图而非"Pro forma"以获取原始AWS定价  
**调查方法**: 对比AWS Console手动配置与代码实现，分析实际部署的CUR配置  
**调查结果**: ❌ **发现严重配置偏差** - 代码实现与预期不符  

## 🔍 调查发现

### 1. AWS Console手动配置分析

从提供的截图可以看到AWS Console中创建CUR的正确方式：

#### Data View选项
- ✅ **Billable** (选中) - 用于获取原始AWS标准定价
- **Pro forma** (未选中) - 用于获取Billing Conductor调整后的价格

#### Billing Group配置
- 当选择"Billable"数据视图时
- Billing group下拉菜单显示"Select billing group"
- **关键**: 可以保持为空，这样就不会应用任何Billing Group的价格调整

### 2. 当前代码实现分析

#### RISP CUR模板代码 (Module 4)
```python
# 在templates/04-cur-risp/cur_export_risp.yaml:233-248
response = cur.put_report_definition(
    ReportDefinition={
        'ReportName': report_name,
        'TimeUnit': 'DAILY',
        'Format': 'Parquet',
        'Compression': 'Parquet',
        'AdditionalSchemaElements': ['RESOURCES'],
        'S3Bucket': bucket_name,
        'S3Prefix': 'daily',
        'S3Region': 'us-east-1',
        'AdditionalArtifacts': ['ATHENA'],
        'RefreshClosedReports': True,
        'ReportVersioning': 'OVERWRITE_REPORT'
        # 注意：这里不包含BillingViewArn，因为不使用Pro forma
    }
)
```

**代码分析**:
- ✅ 代码中确实**没有**包含`BillingViewArn`参数
- ✅ 注释明确说明"不使用Pro forma"
- ✅ 意图是创建标准的Billable CUR报告

### 3. 实际部署配置验证

通过`aws cur describe-report-definitions`命令检查实际配置：

#### RISP CUR报告 (`risp-730335480018`)
```json
{
    "ReportName": "risp-730335480018",
    "BillingViewArn": "arn:aws:billing::730335480018:billingview/primary",
    "ReportStatus": {
        "lastDelivery": "",
        "lastStatus": ""
    }
}
```

#### Pro forma CUR报告 (`730335480018`)
```json
{
    "ReportName": "730335480018", 
    "BillingViewArn": "arn:aws:billing::730335480018:billingview/billing-group-058316962835",
    "ReportStatus": {
        "lastDelivery": "",
        "lastStatus": ""
    }
}
```

## 🚨 关键问题发现

### ❌ 严重配置偏差

**预期配置**:
- RISP CUR应该**没有**`BillingViewArn`参数
- 应该使用纯粹的"Billable"数据视图
- 应该获得原始AWS标准定价

**实际配置**:
- ❌ RISP CUR意外包含了`BillingViewArn`: `arn:aws:billing::730335480018:billingview/primary`
- ❌ 使用了"Primary billing view"而非标准的Billable视图
- ❌ 可能无法获得纯粹的AWS原始定价

### AWS Billing View类型分析

根据当前配置，我们有三种Billing View类型：

1. **Primary Billing View** (当前RISP使用)
   - ARN: `arn:aws:billing::730335480018:billingview/primary`
   - 类型: PRIMARY
   - **问题**: 在有Billing Conductor的账户中，Primary view可能包含一些调整

2. **Billing Group View** (Pro forma使用)
   - ARN: `arn:aws:billing::730335480018:billingview/billing-group-058316962835`
   - 类型: BILLING_GROUP
   - **正确**: 用于Pro forma，应用Billing Conductor的价格调整

3. **纯Billable View** (我们需要的)
   - ARN: 应该**没有**BillingViewArn参数
   - 类型: 标准AWS CUR
   - **目标**: 获得原始AWS标准定价，不受任何调整影响

## 🎯 根本原因分析

### 1. AWS CUR API默认行为

**关键发现**: 在启用了Billing Conductor的AWS账户中：

1. **当不提供BillingViewArn时**
   - AWS **不会**创建纯粹的标准CUR
   - AWS **会自动**关联账户的Primary billing view
   - Primary view在Billing Conductor环境中可能包含调整

2. **这与普通AWS账户的行为不同**
   - 在没有Billing Conductor的账户中，不提供BillingViewArn确实会创建标准CUR
   - 但在Billing Conductor账户中，AWS会默认使用Primary view

### 2. 代码实现与AWS行为的错配

**代码假设**: 不提供BillingViewArn = 标准定价CUR  
**AWS实际行为**: 不提供BillingViewArn = Primary billing view CUR  
**结果**: RISP CUR获得的可能不是纯粹的AWS原始定价

## 📊 对比分析表

| 项目 | 手动Console配置 | 当前代码实现 | 实际部署结果 |
|------|---------------|-------------|-------------|
| **Data View** | Billable (选中) | 意图为Billable | Primary billing view |
| **Billing Group** | 空/未选择 | 不提供BillingViewArn | 自动使用Primary |
| **定价类型** | AWS原始定价 | 期望AWS原始定价 | 可能受Primary view影响 |
| **结果** | ✅ 正确 | ❌ 实现有误 | ❌ 配置错误 |

## 🔧 问题解决方向

### 方案1: 显式指定标准定价 (推荐)

需要研究如何在Billing Conductor环境中明确指定获得标准AWS定价，可能需要：

1. **使用特定的BillingViewArn参数**来指定标准定价视图
2. **或者使用特殊的CUR配置**来绕过Primary billing view
3. **或者创建专门的"standard pricing" billing view**

### 方案2: 验证Primary View的实际内容

等CUR数据生成后，验证Primary billing view是否真的影响了定价：

1. 对比RISP数据与已知的AWS标准定价
2. 检查是否包含Billing Conductor的调整
3. 如果Primary view确实是纯粹的标准定价，则当前配置可接受

### 方案3: 重新配置CUR设置

如果验证确认问题，需要：

1. 删除当前的RISP CUR报告
2. 修改Module 4的实现代码
3. 使用正确的参数重新创建RISP CUR

## 📋 验证清单

### 待验证项目 (CUR数据生成后)

1. **数据内容验证**
   ```sql
   -- 检查RISP数据的定价是否为AWS标准价格
   SELECT DISTINCT 
       line_item_product_code,
       pricing_term,
       line_item_blended_rate,
       line_item_unblended_rate
   FROM risp_table 
   LIMIT 10;
   ```

2. **对比分析**
   ```sql
   -- 比较同一资源在Pro forma和RISP中的价格
   SELECT 
       p.line_item_product_code,
       p.line_item_unblended_cost as proforma_cost,
       r.line_item_unblended_cost as risp_cost,
       CASE 
           WHEN r.line_item_unblended_cost > p.line_item_unblended_cost 
           THEN 'RISP higher (expected for standard pricing)'
           WHEN r.line_item_unblended_cost = p.line_item_unblended_cost 
           THEN 'Same price (potential issue)'
           ELSE 'RISP lower (unexpected)'
       END as price_relationship
   FROM proforma_table p
   JOIN risp_table r ON p.line_item_resource_id = r.line_item_resource_id
   LIMIT 20;
   ```

3. **Billing View影响评估**
   - 检查RISP数据是否包含任何折扣或调整
   - 验证价格是否为AWS官方列表价格
   - 确认Primary billing view的实际作用

## 🎯 结论

### 关键发现
1. ❌ **代码实现与预期配置不符**
2. ❌ **RISP CUR意外使用了Primary billing view**
3. ❌ **可能无法获得纯粹的AWS原始定价**
4. ✅ **代码意图正确，但AWS API行为不符合预期**

### 严重性评估
- **优先级**: 🔴 **高**
- **影响**: 可能导致成本分析基准错误
- **紧急性**: 需要等CUR数据验证后确定修复方案

### 建议行动
1. **立即**: 等待CUR数据生成(24-48小时)
2. **验证**: 检查RISP数据是否真的是AWS标准定价
3. **决策**: 基于验证结果决定是否需要重新配置
4. **修复**: 如果需要，更新Module 4实现并重新部署

### 学习要点
这次调查揭示了在Billing Conductor环境中创建"标准定价"CUR的复杂性，显示了代码实现需要考虑AWS服务在不同环境配置下的不同行为模式。

**状态**: 🟡 **等待数据验证后确定最终修复方案**