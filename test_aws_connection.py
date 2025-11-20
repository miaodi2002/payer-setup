#!/usr/bin/env python3
"""
AWS Connection Test Script
测试AWS凭证是否有效并检查相关权限
"""

import boto3
import sys
from botocore.exceptions import ClientError, NoCredentialsError, PartialCredentialsError

def test_aws_connection(access_key, secret_key):
    """
    测试AWS连接并检查基本权限

    Args:
        access_key: AWS Access Key ID
        secret_key: AWS Secret Access Key

    Returns:
        dict: 测试结果
    """
    results = {
        'connection': False,
        'identity': None,
        'account_id': None,
        'user_arn': None,
        'permissions': {},
        'errors': []
    }

    try:
        # 创建session
        session = boto3.Session(
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name='us-east-1'  # Payer设置通常在us-east-1
        )

        # 测试1: 验证凭证有效性
        print("\n=== 测试 1: 验证AWS凭证 ===")
        sts = session.client('sts')
        identity = sts.get_caller_identity()
        results['connection'] = True
        results['identity'] = identity
        results['account_id'] = identity['Account']
        results['user_arn'] = identity['Arn']

        print(f"✅ AWS凭证有效")
        print(f"   账户ID: {identity['Account']}")
        print(f"   用户ARN: {identity['Arn']}")
        print(f"   User ID: {identity['UserId']}")

        # 测试2: Organizations权限
        print("\n=== 测试 2: Organizations权限 ===")
        try:
            org_client = session.client('organizations', region_name='us-east-1')
            org = org_client.describe_organization()
            results['permissions']['organizations'] = True
            print(f"✅ Organizations权限正常")
            print(f"   组织ID: {org['Organization']['Id']}")
            print(f"   Master账户ID: {org['Organization']['MasterAccountId']}")
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'AccessDeniedException':
                results['permissions']['organizations'] = False
                print(f"⚠️  Organizations权限不足: {e.response['Error']['Message']}")
            elif error_code == 'AWSOrganizationsNotInUseException':
                results['permissions']['organizations'] = 'not_enabled'
                print(f"⚠️  AWS Organizations未启用")
            else:
                raise

        # 测试3: S3权限
        print("\n=== 测试 3: S3权限 ===")
        try:
            s3_client = session.client('s3', region_name='us-east-1')
            buckets = s3_client.list_buckets()
            results['permissions']['s3'] = True
            print(f"✅ S3权限正常 (找到 {len(buckets['Buckets'])} 个存储桶)")
        except ClientError as e:
            results['permissions']['s3'] = False
            print(f"⚠️  S3权限不足: {e.response['Error']['Message']}")

        # 测试4: CloudFormation权限
        print("\n=== 测试 4: CloudFormation权限 ===")
        try:
            cfn_client = session.client('cloudformation', region_name='us-east-1')
            stacks = cfn_client.list_stacks(
                StackStatusFilter=['CREATE_COMPLETE', 'UPDATE_COMPLETE']
            )
            results['permissions']['cloudformation'] = True
            print(f"✅ CloudFormation权限正常")
        except ClientError as e:
            results['permissions']['cloudformation'] = False
            print(f"⚠️  CloudFormation权限不足: {e.response['Error']['Message']}")

        # 测试5: IAM权限
        print("\n=== 测试 5: IAM权限 ===")
        try:
            iam_client = session.client('iam', region_name='us-east-1')
            roles = iam_client.list_roles(MaxItems=1)
            results['permissions']['iam'] = True
            print(f"✅ IAM权限正常")
        except ClientError as e:
            results['permissions']['iam'] = False
            print(f"⚠️  IAM权限不足: {e.response['Error']['Message']}")

        # 测试6: Billing Conductor权限
        print("\n=== 测试 6: Billing Conductor权限 ===")
        try:
            bc_client = session.client('billingconductor', region_name='us-east-1')
            billing_groups = bc_client.list_billing_groups(MaxResults=1)
            results['permissions']['billingconductor'] = True
            print(f"✅ Billing Conductor权限正常")
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'AccessDeniedException':
                results['permissions']['billingconductor'] = False
                print(f"⚠️  Billing Conductor权限不足")
            else:
                results['permissions']['billingconductor'] = False
                print(f"⚠️  Billing Conductor错误: {e.response['Error']['Message']}")

        # 测试7: CUR权限
        print("\n=== 测试 7: Cost and Usage Report (CUR)权限 ===")
        try:
            cur_client = session.client('cur', region_name='us-east-1')
            reports = cur_client.describe_report_definitions(MaxResults=1)
            results['permissions']['cur'] = True
            print(f"✅ CUR权限正常")
        except ClientError as e:
            results['permissions']['cur'] = False
            print(f"⚠️  CUR权限不足: {e.response['Error']['Message']}")

        # 测试8: Lambda权限
        print("\n=== 测试 8: Lambda权限 ===")
        try:
            lambda_client = session.client('lambda', region_name='us-east-1')
            functions = lambda_client.list_functions(MaxItems=1)
            results['permissions']['lambda'] = True
            print(f"✅ Lambda权限正常")
        except ClientError as e:
            results['permissions']['lambda'] = False
            print(f"⚠️  Lambda权限不足: {e.response['Error']['Message']}")

        # 测试9: Glue权限
        print("\n=== 测试 9: Glue权限 ===")
        try:
            glue_client = session.client('glue', region_name='us-east-1')
            databases = glue_client.get_databases(MaxResults=1)
            results['permissions']['glue'] = True
            print(f"✅ Glue权限正常")
        except ClientError as e:
            results['permissions']['glue'] = False
            print(f"⚠️  Glue权限不足: {e.response['Error']['Message']}")

        # 测试10: Athena权限
        print("\n=== 测试 10: Athena权限 ===")
        try:
            athena_client = session.client('athena', region_name='us-east-1')
            workgroups = athena_client.list_work_groups(MaxResults=1)
            results['permissions']['athena'] = True
            print(f"✅ Athena权限正常")
        except ClientError as e:
            results['permissions']['athena'] = False
            print(f"⚠️  Athena权限不足: {e.response['Error']['Message']}")

        # 总结
        print("\n" + "="*60)
        print("测试总结")
        print("="*60)

        total_services = len(results['permissions'])
        passed_services = sum(1 for v in results['permissions'].values() if v == True)

        print(f"\n✅ AWS连接成功!")
        print(f"📊 权限检查: {passed_services}/{total_services} 个服务权限正常")

        if passed_services < total_services:
            print("\n⚠️  需要注意:")
            for service, status in results['permissions'].items():
                if status == False:
                    print(f"   - {service}: 权限不足")
                elif status == 'not_enabled':
                    print(f"   - {service}: 服务未启用")

        print("\n💡 建议:")
        print("   根据README.md中的IAM权限策略要求配置完整权限")
        print("   部署位置: us-east-1 (CUR导出必须在此区域)")

        return results

    except NoCredentialsError:
        print("❌ 错误: 未找到AWS凭证")
        results['errors'].append("NoCredentials")
        return results
    except PartialCredentialsError:
        print("❌ 错误: AWS凭证不完整")
        results['errors'].append("PartialCredentials")
        return results
    except ClientError as e:
        error_msg = f"AWS API错误: {e.response['Error']['Message']}"
        print(f"❌ {error_msg}")
        results['errors'].append(error_msg)
        return results
    except Exception as e:
        error_msg = f"未知错误: {str(e)}"
        print(f"❌ {error_msg}")
        results['errors'].append(error_msg)
        return results


if __name__ == "__main__":
    import os

    print("="*60)
    print("AWS Payer设置 - 连接测试工具")
    print("="*60)

    # 从环境变量或命令行参数获取凭证
    access_key = os.environ.get('AWS_ACCESS_KEY_ID')
    secret_key = os.environ.get('AWS_SECRET_ACCESS_KEY')

    if not access_key or not secret_key:
        print("\n请设置环境变量:")
        print("  export AWS_ACCESS_KEY_ID='your-access-key'")
        print("  export AWS_SECRET_ACCESS_KEY='your-secret-key'")
        print("\n或者作为命令行参数传递:")
        print("  python3 test_aws_connection.py <access_key> <secret_key>")

        if len(sys.argv) >= 3:
            access_key = sys.argv[1]
            secret_key = sys.argv[2]
        else:
            sys.exit(1)

    results = test_aws_connection(access_key, secret_key)

    # 返回适当的退出码
    if results['connection']:
        sys.exit(0)
    else:
        sys.exit(1)
