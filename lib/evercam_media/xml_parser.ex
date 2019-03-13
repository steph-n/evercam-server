defmodule EvercamMedia.XMLParser do
  require Record
  Record.defrecord :xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecord :xmlText,    Record.extract(:xmlText,    from_lib: "xmerl/include/xmerl.hrl")

  def parse_single(text, node) do
    text
    |> String.to_charlist
    |> :xmerl_scan.string
    |> parse_single_element(node)
  end

  def parse_inner_array(text) do
    text
    |> String.to_charlist
    |> :xmerl_scan.string
  end

  def parse_xml(text, node) do
    text
    |> String.to_charlist
    |> :xmerl_scan.string
    |> parse(node)
  end

  def parse({ xml, _ }, node) do
    elements   = :xmerl_xpath.string(node, xml)

    Enum.map(
      elements,
      fn(element) ->
        [text] = xmlElement(element, :content)
        xmlText(text, :value) |> to_string
      end
    )
  end

  def parse_single_element({ xml, _ }, node) do
    case :xmerl_xpath.string(node, xml) do
      [element] ->
        [text] = xmlElement(element, :content)
        xmlText(text, :value) |> to_string
      [] -> ""
    end
  end

  def parse_inner({ xml, _ }, node) do
    elements   = :xmerl_xpath.string(node, xml)
    Enum.map(elements, fn(element) -> element end)
  end

  def parse_element(xml_element, node) do
    case :xmerl_xpath.string(node, xml_element) do
      [element] -> parse_text(element)
      [] -> ""
      list -> list |> List.first |> parse_text
    end
  end

  def parse_text(element) do
    case xmlElement(element, :content) do
      [text] -> xmlText(text, :value) |> to_string
      [] -> ""
    end
  end
end
