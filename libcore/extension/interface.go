package extension

import (
	"fmt"

	"github.com/hiddify/hiddify-core/v2/db"
	"github.com/sagernet/sing-box/log"

	"github.com/hiddify/hiddify-core/v2/service_manager"
)

var (
	allExtensionsMap     = make(map[string]ExtensionFactory)
	enabledExtensionsMap = make(map[string]*Extension)
)

func RegisterExtension(factory ExtensionFactory) error {
	if _, ok := allExtensionsMap[factory.Id]; ok {
		err := fmt.Errorf("Extension with ID %s already exists", factory.Id)
		log.Warn(err)
		return err
	}

	table := db.GetTable[extensionData]()
	data, err := table.Get(factory.Id)
	if data == nil || err != nil {
		log.Warn("Data of Extension ", factory.Id, " not found, creating new one")
		data = &extensionData{Id: factory.Id, Enable: false}
		if err := table.UpdateInsert(data); err != nil {
			log.Warn("Failed to create new extension data: ", err, " ", factory.Id)
			return err
		}
	}

	allExtensionsMap[factory.Id] = factory

	return nil
}

func isEnable(id string) bool {
	table := db.GetTable[extensionData]()
	extdata, err := table.Get(id)
	if err != nil {
		return false
	}
	return extdata.Enable
}

func loadExtension(factory ExtensionFactory) error {
	if !isEnable(factory.Id) {
		return fmt.Errorf("Extension with ID %s is not enabled", factory.Id)
	}
	extension := factory.Builder()
	extension.init(factory.Id)

	// fmt.Printf("Registered extension: %+v\n", extension)
	enabledExtensionsMap[factory.Id] = &extension

	return nil
}

type extensionService struct {
	// Storage *CacheFile
}

func (s *extensionService) Start() error {
	table := db.GetTable[extensionData]()
	extdata, err := table.All()
	if err != nil {
		log.Warn("failed to select enabled extensions: ", err, " (extensions disabled)")
		return nil
	}
	for _, data := range extdata {
		if !data.Enable {
			continue
		}
		if factory, ok := allExtensionsMap[data.Id]; ok {
			if err := loadExtension(factory); err != nil {
				log.Warn("failed to load extension ", data.Id, ": ", err)
				continue
			}
		} else {
			log.Warn("extension ", data.Id, " is enabled but not found")
			continue
		}
	}
	return nil
}

func (s *extensionService) Close() error {
	for _, extension := range enabledExtensionsMap {
		if err := (*extension).Close(); err != nil {
			return err
		}
	}
	return nil
}

func init() {
	service_manager.Register(&extensionService{})
}
