module Backend
  class EasyticketImportRunsBroadcaster
    def self.broadcast!
      Backend::ImportRunsBroadcaster.broadcast!
    end
  end
end
