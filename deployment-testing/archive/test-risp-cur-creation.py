#!/usr/bin/env python3
"""
测试脚本：在Billing Conductor环境中创建真正的标准定价CUR
"""

import boto3
import json
import time

def test_risp_cur_creation():
    """测试不同的RISP CUR创建方法"""
    
    cur = boto3.client('cur', region_name='us-east-1')
    
    # 基础配置
    account_id = "730335480018"
    bucket_name = f"bip-risp-cur-{account_id}"
    report_name = f"risp-{account_id}"
    
    # 基础CUR定义
    base_definition = {
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
    }
    
    # 尝试不同的方法
    methods = [
        {
            'name': 'Method 1: 完全不提供BillingViewArn (原始方法)',
            'definition': base_definition.copy()
        },
        {
            'name': 'Method 2: 明确指定空的BillingViewArn',
            'definition': {**base_definition.copy(), 'BillingViewArn': ''}
        },
        {
            'name': 'Method 3: 使用None值',
            'definition': {**base_definition.copy(), 'BillingViewArn': None}
        }
    ]
    
    for i, method in enumerate(methods):
        print(f"\n=== {method['name']} ===")
        
        try:
            # 清理BillingViewArn如果值为空或None
            definition = method['definition'].copy()
            if 'BillingViewArn' in definition and (definition['BillingViewArn'] == '' or definition['BillingViewArn'] is None):
                del definition['BillingViewArn']
            
            print(f"正在尝试创建CUR...")
            print(f"定义: {json.dumps(definition, indent=2, default=str)}")
            
            response = cur.put_report_definition(ReportDefinition=definition)
            print(f"✅ 成功创建！响应: {response}")
            
            # 等待一下然后检查实际配置
            time.sleep(2)
            
            # 检查实际创建的CUR配置
            reports = cur.describe_report_definitions()
            for report in reports['ReportDefinitions']:
                if report['ReportName'] == report_name:
                    billing_view = report.get('BillingViewArn', 'NOT_SET')
                    print(f"✅ 实际配置 - BillingViewArn: {billing_view}")
                    
                    if billing_view == 'NOT_SET':
                        print(f"🎯 成功！没有BillingViewArn，这应该是纯标准定价")
                        return True
                    else:
                        print(f"❌ 仍然有BillingViewArn: {billing_view}")
                        # 删除这个测试CUR继续下一个方法
                        print(f"删除测试CUR...")
                        cur.delete_report_definition(ReportName=report_name)
                        time.sleep(1)
                        break
            
        except Exception as e:
            print(f"❌ 方法失败: {str(e)}")
            continue
    
    print(f"\n❌ 所有方法都失败了，需要研究其他解决方案")
    return False

if __name__ == "__main__":
    test_risp_cur_creation()