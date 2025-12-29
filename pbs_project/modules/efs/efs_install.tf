resource "kubernetes_storage_class" "efs_sc" {
  metadata {
    name = "efs-sc" # 개발자들이 이 이름을 쓸 수 있게 해줘야 합니다.
  }
  storage_provisioner = "efs.csi.aws.com"
  reclaim_policy      = "Retain"
  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = "fs-0109bfcbcf364ee3e" # 형님이 가진 고유 ID 연결
    directoryPerms   = "700"
  }
}