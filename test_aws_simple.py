#!/usr/bin/env python3
"""
简单的AWS连接测试
"""

import boto3
import sys
from botocore.exceptions import ClientError, NoCredentialsError

def test_basic_connection(access_key, secret_key):
    """基本的AWS连接测试"""

    print("="*60)
    print("AWS基本连接测试")
    print("="*60)
    print(f"\nAccess Key ID: {access_key}")
    print(f"Secret Key: {secret_key[:10]}...{secret_key[-4:]}")

    try:
        # 测试STS GetCallerIdentity - 这是最基本的API调用
        print("\n正在测试AWS STS GetCallerIdentity...")

        sts = boto3.client(
            'sts',
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name='us-east-1'
        )

        response = sts.get_caller_identity()

        print("\n✅ AWS连接成功!")
        print(f"   账户ID: {response['Account']}")
        print(f"   用户ARN: {response['Arn']}")
        print(f"   User ID: {response['UserId']}")

        return True

    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_msg = e.response['Error']['Message']
        print(f"\n❌ AWS API错误:")
        print(f"   错误代码: {error_code}")
        print(f"   错误信息: {error_msg}")

        if error_code == 'InvalidClientTokenId':
            print("\n⚠️  可能的原因:")
            print("   1. Access Key ID不正确或已被删除")
            print("   2. 凭证可能属于已删除的IAM用户")
        elif error_code == 'SignatureDoesNotMatch':
            print("\n⚠️  可能的原因:")
            print("   1. Secret Access Key不正确")
            print("   2. 凭证中可能包含特殊字符导致签名错误")
        elif error_code == 'AccessDenied':
            print("\n⚠️  可能的原因:")
            print("   1. 凭证有效但被拒绝访问")
            print("   2. IAM用户权限不足")

        return False

    except NoCredentialsError:
        print("\n❌ 未找到AWS凭证")
        return False

    except Exception as e:
        print(f"\n❌ 未知错误: {type(e).__name__}")
        print(f"   详细信息: {str(e)}")

        # 打印更多调试信息
        import traceback
        print("\n完整错误栈:")
        traceback.print_exc()

        return False


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("使用方法: python3 test_aws_simple.py <access_key> <secret_key>")
        sys.exit(1)

    access_key = sys.argv[1]
    secret_key = sys.argv[2]

    success = test_basic_connection(access_key, secret_key)

    sys.exit(0 if success else 1)
