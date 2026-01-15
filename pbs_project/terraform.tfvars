# 파일 위치: pbs_project/terraform.tfvars

project_name = "pbs-project"
region       = "ap-northeast-2"
vpc_cidr     = "10.0.0.0/18"
environment = "dev"
github_token = "" # 깃 푸쉬 x, 사용시에만 넣어서 쓸 것.
# 여기에 팀원들을 계속 추가하면 됩니다.
team_members = [
  "arn:aws:iam::198011705652:user/kkh_soldesk",
  "arn:aws:iam::198011705652:user/ssw_soldesk",  # ssw 님
  # "arn:aws:iam::198011705652:user/cgy_soldesk",   # cgy 님
  "arn:aws:iam::198011705652:user/kdh_soldesk",
  "arn:aws:iam::198011705652:user/cmw_soldesk"
]