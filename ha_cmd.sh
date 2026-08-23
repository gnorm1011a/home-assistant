cd /config
git add -A
git status --short
echo "---"
git commit -F /config/commit_msg.txt
rm /config/commit_msg.txt
echo "---"
git log --oneline -3
