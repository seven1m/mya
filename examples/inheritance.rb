class Animal
  def initialize(name)
    @name = name
  end

  def name
    @name
  end

  def speak
    puts @name + ' makes a sound'
  end

  def move
    puts @name + ' moves around'
  end
end

class Dog < Animal
  def initialize(name, breed)
    @name = name
    @breed = breed
  end

  def speak
    puts @name + ' barks: Woof!'
  end

  def breed
    @breed
  end

  def fetch
    puts @name + ' fetches the ball'
  end
end

class Cat < Animal
  def speak
    puts @name + ' meows: Meow!'
  end

  def climb
    puts @name + ' climbs a tree'
  end
end

animal = Animal.new('Generic Animal')
animal.speak
animal.move

puts ''

dog = Dog.new('Buddy', 'Golden Retriever')
puts 'Dog name: ' + dog.name
puts 'Dog breed: ' + dog.breed
dog.speak # Overridden method
dog.move # Inherited method
dog.fetch # Own method

puts ''

cat = Cat.new('Whiskers')
puts 'Cat name: ' + cat.name
cat.speak # Overridden method
cat.move # Inherited method
cat.climb # Own method
