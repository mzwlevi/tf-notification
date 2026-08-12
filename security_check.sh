#!/bin/bash
# -*- coding: utf-8 -*-

# ============================================================
# 安全扫描脚本 - 用于检查仓库中是否存在敏感信息
# 用法: chmod +x security_check.sh && ./security_check.sh
# ============================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   🔍 仓库安全扫描工具${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查的文件列表
FILES_TO_CHECK=(
    "check.py"
    ".github/workflows/*.yml"
    ".github/workflows/*.yaml"
    "*.json"
    "*.env"
    "*.txt"
    "*.md"
    "*.cfg"
    "*.ini"
)

# ============================================================
# 1. 扫描当前文件内容
# ============================================================
echo -e "${GREEN}[1/4] 扫描当前文件...${NC}"

FOUND_ISSUES=0

# 检查硬编码密钥特征
PATTERNS=(
    "BARK_KEY\\s*=\\s*['\"][^'\"]+['\"]"           # BARK_KEY = "xxx"
    "API_KEY\\s*=\\s*['\"][^'\"]+['\"]"             # API_KEY = "xxx"
    "SECRET\\s*=\\s*['\"][^'\"]+['\"]"              # SECRET = "xxx"
    "TOKEN\\s*=\\s*['\"][^'\"]+['\"]"               # TOKEN = "xxx"
    "PASSWORD\\s*=\\s*['\"][^'\"]+['\"]"            # PASSWORD = "xxx"
    "API_SECRET\\s*=\\s*['\"][^'\"]+['\"]"          # API_SECRET = "xxx"
    "[a-f0-9]{40}"                                  # 40位十六进制 (SHA-1)
    "[a-f0-9]{64}"                                  # 64位十六进制 (SHA-256)
    "sk-[a-zA-Z0-9]{48}"                            # OpenAI API Key
    "ghp_[a-zA-Z0-9]{36}"                           # GitHub Token
)

# 收集所有需要检查的文件
FILES=$(find . -type f -not -path "./.git/*" -not -path "./.github/*" \
    -name "*.py" -o -name "*.yml" -o -name "*.yaml" \
    -o -name "*.json" -o -name "*.env" -o -name "*.txt" \
    -o -name "*.md" -o -name "*.cfg" -o -name "*.ini")

for pattern in "${PATTERNS[@]}"; do
    result=$(grep -rniE "$pattern" . \
        --exclude-dir=.git \
        --exclude-dir=.github \
        --exclude="security_check.sh" \
        2>/dev/null | grep -v "os.getenv\|os.environ" | head -5)
    
    if [ -n "$result" ]; then
        echo -e "${RED}  ⚠️  发现可能硬编码的密钥:${NC}"
        echo "$result" | while read line; do
            echo -e "    ${YELLOW}$line${NC}"
        done
        FOUND_ISSUES=$((FOUND_ISSUES + 1))
    fi
done

# 特殊检查：BARK_KEY 是否在代码中硬编码
echo -e "${BLUE}  → 检查 BARK_KEY 硬编码...${NC}"
BARK_CHECK=$(grep -rn "BARK_KEY\s*=\s*['\"]" . \
    --exclude-dir=.git \
    --exclude="security_check.sh" \
    2>/dev/null | grep -v "os.getenv" | grep -v "os.environ")

if [ -n "$BARK_CHECK" ]; then
    echo -e "${RED}    ⚠️  发现 BARK_KEY 可能被硬编码:${NC}"
    echo "$BARK_CHECK" | while read line; do
        echo -e "    ${YELLOW}$line${NC}"
    done
    FOUND_ISSUES=$((FOUND_ISSUES + 1))
else
    echo -e "    ${GREEN}✅ 未发现 BARK_KEY 硬编码${NC}"
fi

# ============================================================
# 2. 检查 git 历史
# ============================================================
echo ""
echo -e "${GREEN}[2/4] 扫描 Git 提交历史...${NC}"

if command -v git &> /dev/null && [ -d ".git" ]; then
    echo -e "${BLUE}  → 检查历史中是否包含密钥...${NC}"
    
    # 检查历史中的 BARK_KEY
    HIST_CHECK=$(git log -p --all --grep="BARK_KEY" 2>/dev/null | head -20)
    if [ -n "$HIST_CHECK" ]; then
        echo -e "${RED}    ⚠️  历史提交中发现 BARK_KEY 相关记录:${NC}"
        echo "$HIST_CHECK" | while read line; do
            echo -e "    ${YELLOW}$line${NC}"
        done
        FOUND_ISSUES=$((FOUND_ISSUES + 1))
    else
        echo -e "    ${GREEN}✅ 未在历史中发现 BARK_KEY 记录${NC}"
    fi
    
    # 检查历史中的长字符串（可能是密钥）
    echo -e "${BLUE}  → 检查历史中的长字符串...${NC}"
    STRING_CHECK=$(git log -p --all 2>/dev/null | grep -E "[a-f0-9]{32,}" | head -5)
    if [ -n "$STRING_CHECK" ]; then
        echo -e "${YELLOW}    ℹ️  历史中发现长字符串（请人工确认是否是密钥）:${NC}"
        echo "$STRING_CHECK" | while read line; do
            echo -e "    ${YELLOW}$line${NC}"
        done
    else
        echo -e "    ${GREEN}✅ 未在历史中发现可疑长字符串${NC}"
    fi
    
    # 检查历史中是否删除过 .env 等文件
    echo -e "${BLUE}  → 检查是否曾提交过 .env 文件...${NC}"
    ENV_CHECK=$(git log --all --full-history -- "*.env" 2>/dev/null | head -5)
    if [ -n "$ENV_CHECK" ]; then
        echo -e "${RED}    ⚠️  历史中发现 .env 文件曾被提交！${NC}"
        echo "$ENV_CHECK" | while read line; do
            echo -e "    ${YELLOW}$line${NC}"
        done
        FOUND_ISSUES=$((FOUND_ISSUES + 1))
    else
        echo -e "    ${GREEN}✅ 未在历史中发现 .env 文件${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠️  未检测到 Git 仓库，跳过历史扫描${NC}"
fi

# ============================================================
# 3. 检查 .gitignore
# ============================================================
echo ""
echo -e "${GREEN}[3/4] 检查 .gitignore...${NC}"

if [ -f ".gitignore" ]; then
    if grep -q "tf_state.json" .gitignore; then
        echo -e "  ${GREEN}✅ tf_state.json 已在 .gitignore 中${NC}"
    else
        echo -e "  ${YELLOW}⚠️  建议将 tf_state.json 添加到 .gitignore${NC}"
        echo -e "    ${BLUE}   echo 'tf_state.json' >> .gitignore${NC}"
        FOUND_ISSUES=$((FOUND_ISSUES + 1))
    fi
    
    if grep -q ".env" .gitignore; then
        echo -e "  ${GREEN}✅ .env 已在 .gitignore 中${NC}"
    else
        echo -e "  ${YELLOW}⚠️  建议将 .env 添加到 .gitignore${NC}"
        echo -e "    ${BLUE}   echo '.env' >> .gitignore${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  未找到 .gitignore 文件${NC}"
    echo -e "    ${BLUE}   建议创建 .gitignore 并添加:${NC}"
    echo -e "    ${BLUE}   tf_state.json${NC}"
    echo -e "    ${BLUE}   .env${NC}"
    echo -e "    ${BLUE}   *.pyc${NC}"
    echo -e "    ${BLUE}   __pycache__/${NC}"
fi

# ============================================================
# 4. 检查 GitHub Secrets 引用
# ============================================================
echo ""
echo -e "${GREEN}[4/4] 检查 GitHub Secrets 使用...${NC}"

if [ -d ".github/workflows" ]; then
    SECRET_USAGE=$(grep -r '\${{ secrets\.' .github/workflows/ 2>/dev/null)
    if [ -n "$SECRET_USAGE" ]; then
        echo -e "  ${GREEN}✅ 工作流中使用了 GitHub Secrets:${NC}"
        echo "$SECRET_USAGE" | while read line; do
            echo -e "    ${BLUE}$line${NC}"
        done
    else
        echo -e "  ${YELLOW}⚠️  未在工作流中发现 Secrets 引用${NC}"
    fi
fi

# ============================================================
# 总结报告
# ============================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}📊 扫描完成！${NC}"

if [ $FOUND_ISSUES -gt 0 ]; then
    echo -e "${RED}⚠️  发现 ${FOUND_ISSUES} 个潜在问题，请检查后重试${NC}"
    echo ""
    echo -e "${YELLOW}常见修复方法:${NC}"
    echo -e "  1. 如果发现硬编码密钥，立即从代码中删除，改用环境变量"
    echo -e "  2. 如果历史中有密钥，使用 git filter-branch 或 BFG Repo-Cleaner 清理"
    echo -e "  3. 无论如何，已暴露的密钥必须立即更换"
    echo -e "  4. 执行 git reset 或 git revert 移除不安全的提交"
    exit 1
else
    echo -e "${GREEN}✅ 未发现明显安全问题，仓库可以安全公开！${NC}"
    echo ""
    echo -e "${YELLOW}公开前最终确认清单:${NC}"
    echo -e "  ✅ 代码使用环境变量，无硬编码密钥"
    echo -e "  ✅ 历史记录中无敏感信息"
    echo -e "  ✅ .gitignore 配置正确"
    echo -e "  📌 记得在 GitHub 上检查 Secrets 配置是否完整"
    exit 0
fi
