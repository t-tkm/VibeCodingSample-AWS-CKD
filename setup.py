import setuptools

with open("README.md") as fp:
    long_description = fp.read()

setuptools.setup(
    name="dify_cdk",
    version="0.0.1",
    description="AWS CDK プロジェクト - Dify デプロイメント",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="CDK User",
    package_dir={"": "dify_cdk"},
    packages=setuptools.find_packages(where="dify_cdk"),
    install_requires=[
        "aws-cdk-lib>=2.0.0",
        "constructs>=10.0.0",
        "aws-cdk.aws-ec2-alpha>=2.0.0a0",
        "aws-cdk.aws-ssm-alpha>=2.0.0a0",
    ],
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
)
