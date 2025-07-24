# CUR技术实现方案

## 方案概述

基于AWS代理商业务需求，设计两套独立的CUR配置来满足不同的数据用途。

## 🎯 技术实现策略

### Pro forma CUR (客户可见"原价")
**当前状态**: ✅ 配置正确  
**技术方案**: 保持现有配置

```yaml
配置详情:
  ReportName: "730335480018"
  BillingViewArn: "arn:aws:billing::730335480018:billingview/billing-group-058316962835"
  Purpose: 客户可见的AWS标准价格基准
  验证状态: 已正确配置
```

### RISP CUR (代理商真实成本)
**当前状态**: ❌ 配置错误  
**问题**: 使用了Primary billing view而非代理商真实成本  
**技术方案**: 需要重新配置

## 🔧 RISP CUR解决方案分析

### 问题根因
在启用Billing Conductor的AWS账户中：
- 不提供BillingViewArn → AWS自动使用Primary billing view
- Primary billing view ≠ 代理商真实成本数据
- 需要找到获得真实代理商成本的正确方法

### 技术方案选项

#### 方案A: 使用账户级别的真实成本视图 (推荐)
**原理**: 创建或使用代表代理商真实成本的billing view
**实现**: 
```bash
# 可能需要的配置
BillingViewArn: "arn:aws:billing::730335480018:billingview/reseller-actual-cost"
或者
# 使用特定的账户级别配置
```

**优势**: 
- ✅ 直接获得代理商真实成本
- ✅ 包含所有代理商折扣和credit
- ✅ 数据准确性高

**风险**: 
- 需要验证AWS是否提供这种billing view类型

#### 方案B: 通过Master Account的账户级别CUR
**原理**: 在Master Account层面创建不关联任何特定billing group的CUR
**实现**:
```bash
# 可能的解决方法
1. 在不同的AWS区域创建CUR
2. 使用Management Account的原生成本数据
3. 通过Cost and Billing API直接获取
```

**优势**:
- ✅ 绕过Billing Conductor的限制
- ✅ 获得真实的账户级别成本

**风险**:
- 实现复杂性较高
- 可能需要额外的数据处理

#### 方案C: 验证Primary Billing View的实际内容
**原理**: 测试Primary billing view是否实际包含代理商真实成本
**实现**:
```bash
# 等待CUR数据生成后验证
1. 检查Primary view数据是否包含代理商折扣
2. 对比已知的AWS账单数据
3. 确认数据准确性
```

**优势**:
- ✅ 如果Primary view正确，无需修改
- ✅ 实现简单

**风险**:
- 如果Primary view不准确，仍需其他方案

## 🚀 推荐实施方案

### 第一阶段: 快速验证 (推荐立即执行)
1. **删除当前错误的RISP CUR**
2. **研究Master Account的billing view选项**
3. **尝试创建不使用任何特定billing group的CUR**

### 实施步骤
```bash
# Step 1: 删除当前RISP CUR
aws cur delete-report-definition --report-name risp-730335480018 --region us-east-1

# Step 2: 尝试在不同配置下创建新的RISP CUR
# 方案测试序列:
1. 尝试强制不使用BillingViewArn
2. 尝试使用Master Account级别的billing view
3. 验证哪种配置产生正确的代理商成本数据
```

### 第二阶段: 数据验证
一旦新RISP CUR开始生成数据：
1. **对比历史AWS账单**验证数据准确性
2. **检查代理商折扣**是否正确包含
3. **验证Credit抵扣**是否体现在数据中

## 📋 技术验证清单

### Pro forma CUR验证 (已完成)
- [x] 使用正确的billing group
- [x] 配置为显示标准AWS价格
- [x] 客户账号正确关联

### RISP CUR验证 (待实施)
- [ ] 删除错误配置的当前RISP CUR
- [ ] 实施新的RISP CUR配置方案
- [ ] 验证数据包含代理商真实成本
- [ ] 确认数据保密性

## 🔍 方案风险评估

### 技术风险
- **中等**: AWS Billing Conductor环境的复杂性
- **低**: Pro forma CUR已验证工作正常
- **中等**: RISP CUR可能需要多次尝试找到正确配置

### 业务风险
- **高**: 如果RISP数据不准确，影响成本分析
- **低**: Pro forma数据已正常，客户业务不受影响
- **中等**: 测试期间可能需要临时的数据收集方案

## 💡 实施建议

### 立即可执行的行动
1. **删除错误的RISP CUR** - 避免继续生成错误数据
2. **研究正确的配置方法** - 测试不同的billing view配置
3. **准备验证标准** - 定义如何验证RISP数据的准确性

### 需要您确认的技术选择
1. **优先尝试哪个方案** (A/B/C)？
2. **是否接受短期的RISP数据中断** 来实施正确配置？
3. **如何验证RISP数据准确性** (对比历史账单数据)？

---
**方案状态**: 等待Review和技术选择确认  
**下一步**: 根据您的feedback开始技术实施