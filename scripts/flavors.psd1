# The game flavors this repo builds for, one entry each. Every script reads this file, so a
# new flavor is a new entry here and a folder under AddonProjects, not five edits.
#
#   Folder     the client folder under the WoW install, where Interface\AddOns lives
#   Interface  the .toc interface number the flavor's addons target
#   Library    the shared library addon the flavor's addons depend on
#   Published  what release.ps1 packages for CurseForge, in upload order (library first)
#   Template   the addon new-addon.ps1 copies from; empty while the flavor has none
@{
    era = @{
        Folder = "_classic_era_"; Interface = "11508"; Library = "ICLibs"
        Published = @(); Template = "ICTemplate"
    }
    anniversary = @{
        Folder = "_anniversary_"; Interface = "20506"; Library = "ICLibs"
        # AuctionatorSellingTweaks, CutMaster and ICTemplate stay local on purpose.
        Published = @("ICLibs", "MalexisAuctionWatcher", "TradeMaster", "GuildRecruitment", "MarkedForDeath")
        Template = "ICTemplate"
    }
    retail = @{
        Folder = "_retail_"; Interface = "120100"; Library = "ICLibs"
        Published = @(); Template = "ICTemplate"
    }
    # WoW Forever. The beta installs as _classic_beta_; when the live client lands under
    # another folder name, this is the one line to change.
    forever = @{
        Folder = "_classic_beta_"; Interface = "16001"; Library = "ICKit"
        Published = @(); Template = ""
    }
}
