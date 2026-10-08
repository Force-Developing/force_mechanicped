-- Runs once force_mechanicped knows the framework is "custom": Config.Framework = "custom", or "auto" when none
-- of qbx_core, es_extended and qb-core is installed. Keep your code inside this function.
RegisterFramework("custom", function()
  --- TODO: the player's balance. Without it nobody can pay (unless Config.Price = 0).
  --- @param source number
  --- @param account "cash"|"bank"
  --- @return number|nil balance, nil when the player isn't loaded
  function GetMoney(source, account)
    return nil
  end

  --- TODO: take the money. Return true only when it was removed.
  --- @return boolean
  function RemoveMoney(source, account, amount)
    return false
  end

  --- TODO: give the money back (refund after a failed repair).
  --- @return boolean
  function AddMoney(source, account, amount)
    return false
  end

  --- TODO: number of players with one of the mechanic jobs. 0 means the NPC always works.
  --- @param jobs table<string, true> e.g. { mechanic = true }
  --- @param onlyOnDuty boolean
  --- @return number
  function CountMechanics(jobs, onlyOnDuty)
    return 0
  end
end)
