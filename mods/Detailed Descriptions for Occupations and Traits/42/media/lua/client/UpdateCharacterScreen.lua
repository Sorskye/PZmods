ISCharacterScreen.loadTraits = function(self)
	for _,image in ipairs(self.traits) do
		self:removeChild(image)
	end
	table.wipe(self.traits);
	self:setDisplayedTraits()
	for _,trait in ipairs(self.displayedTraits) do
		local textImage = ISImage:new(0, 0, trait:getTexture():getWidthOrig(), trait:getTexture():getHeightOrig(), trait:getTexture());
		textImage:initialise();
		textImage:setMouseOverText(trait:getLabel() .. "\n\n" .. trait:getDescription());
		textImage:setVisible(false);
		textImage.trait = trait;
		self:addChild(textImage);
		table.insert(self.traits, textImage);
	end
	self.Strength = self.char:getPerkLevel(Perks.Strength)
	self.Fitness = self.char:getPerkLevel(Perks.Fitness)
end

ISCharacterScreen.loadProfession = function(self)
	self.professionTexture = nil;
	self.profession = nil;
	if self.char:getDescriptor() and self.char:getDescriptor():getCharacterProfession() then
		local characterProfessionDefinition = CharacterProfessionDefinition.getCharacterProfessionDefinition(self.char:getDescriptor():getCharacterProfession());
		if characterProfessionDefinition then
			if not characterProfessionDefinition:getTexture() then
				self.profession = characterProfessionDefinition:getUIName();
			else
				self.profession = characterProfessionDefinition:getUIName() .. "\n\n" .. characterProfessionDefinition:getDescription();
			end
			self.professionTexture = characterProfessionDefinition:getTexture();
		end
	end
end